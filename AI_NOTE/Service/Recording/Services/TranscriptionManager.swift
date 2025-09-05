import Foundation
import AVFoundation
import CoreData

actor TranscriptionManager {
    private let sessionDir: URL
    private let transcript: Transcript
    private let transcriber: Transcriber
    
    private let context: NSManagedObjectContext

    // Очередь и флаги работы
    private var queue: [(URL, Int)] = []
    private var isRunning = false

    // Анти-дубли: индексы уже поставленные в очередь и уже обработанные
    private var enqueuedIdx = Set<Int>()
    private var processedIdx = Set<Int>()

    // Последняя записанная строка (анти-дубль «подряд идентичных»)
    private var lastWrittenText: String? = nil

    init(sessionDir: URL, transcript: Transcript, transcriber: Transcriber, context: NSManagedObjectContext) {
        self.sessionDir = sessionDir
        self.transcript = transcript
        self.transcriber = transcriber
        self.context = context
    }

    /// Кладём файл в очередь, если его индекс ещё не обрабатывается и не был обработан
    func enqueue(url: URL, index: Int) {
        guard !processedIdx.contains(index), !enqueuedIdx.contains(index) else { return }
        enqueuedIdx.insert(index)
        queue.append((url, index))
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        print("Transcription worker started")

        // Однажды создаём индексатор для папки сессии
        let indexer = FileIndexer(dir: sessionDir)

        // Стартовый захват *.pending.wav
        for url in indexer.untranscribed() {
            let idx = SegmentFiles.index(from: url)
            guard !processedIdx.contains(idx), !enqueuedIdx.contains(idx) else { continue }
            enqueuedIdx.insert(idx)
            queue.append((url, idx))
        }

        // Главный цикл
        while true {
            if let (url, idx) = queue.sorted(by: { $0.1 < $1.1 }).first {
                // убрать из очереди первую найденную запись с этим URL
                if let i = queue.firstIndex(where: { $0.0 == url }) { queue.remove(at: i) }
                await process(url: url, index: idx)
                continue
            }

            // Пусто — подождать и пересканировать
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for u in indexer.untranscribed() {
                let idx = SegmentFiles.index(from: u)
                guard !processedIdx.contains(idx), !enqueuedIdx.contains(idx) else { continue }
                enqueuedIdx.insert(idx)
                queue.append((u, idx))
            }
        }
    }

    /// Обработка одного сегмента (pending → processing → done)
    private func process(url: URL, index: Int) async {
        // Защита: если уже обработан — выходим
        if processedIdx.contains(index) { return }

        let fm = FileManager.default
        let processingURL = SegmentFiles.processingURL(for: url)

        // Этот индекс теперь не «в очереди», а «в работе»
        enqueuedIdx.remove(index)

        // Переименовать pending → processing (если не вышло, но .processing уже есть — продолжим)
        do {
            try fm.moveItem(at: url, to: processingURL)
        } catch {
            if !fm.fileExists(atPath: processingURL.path) {
                // ни pending, ни processing — видимо, файл пропал; выходим
                return
            }
        }

        do {
            // Транскрибация
            let (rawText, confidence) = try await transcriber.transcribe(file: processingURL)

            // Санитайз и мусор-фильтр
            let printable = TextFilter.sanitize(rawText)
            if !TextFilter.shouldDrop(printable) && printable != lastWrittenText {
                // Вычисляем временные метки
                let chunkSec = (try? AVAudioFile(forReading: processingURL).durationSeconds) ?? 10.0
                let startMs = Int32(max(0.0, Double(index - 1) * chunkSec) * 1000)
                let endMs = Int32((Double(index - 1) * chunkSec + chunkSec) * 1000)
                
                // Сохраняем в БД
                await transcript.addSegment(
                    text: printable,
                    startMs: startMs,
                    endMs: endMs,
                    index: Int32(index),
                    confidence: confidence,
                    context: self.context,
                    source: processingURL.deletingLastPathComponent().lastPathComponent == SourceName.mic.rawValue ? .mic : .system
                )
                
                lastWrittenText = printable
            }

            // Пометить индекс как обработанный
            processedIdx.insert(index)

            // processing → done
            let doneURL = SegmentFiles.doneURL(for: processingURL)
            try? fm.moveItem(at: processingURL, to: doneURL)

            // немедленное удаление: .done → .deleting → unlink
            let deletingURL = SegmentFiles.deletingURL(for: doneURL)
            try? fm.moveItem(at: doneURL, to: deletingURL)   // атомарный «захват»
            try? fm.removeItem(at: deletingURL)              // идемпотентно

        } catch {
            fputs("Transcribe error: \(error)\n", stderr)
            // Возврат в pending, если .processing ещё существует
            if fm.fileExists(atPath: processingURL.path) {
                let backURL = URL(fileURLWithPath: processingURL.path
                    .replacingOccurrences(of: ".processing.", with: ".pending."))
                try? fm.moveItem(at: processingURL, to: backURL)
            }
        }
    }
}
