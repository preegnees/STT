import Foundation
import AVFoundation

actor TranscriptionManager {
    private let session: Session
    private let transcriber: Transcriber
    private let writer: TranscriptWriter

    // Очередь и флаги работы
    private var queue: [(URL, Int)] = []
    private var isRunning = false

    // Анти-дубли: индексы уже поставленные в очередь и уже обработанные
    private var enqueuedIdx = Set<Int>()
    private var processedIdx = Set<Int>()

    // Последняя записанная строка (анти-дубль «подряд идентичных»)
    private var lastWrittenLine: String? = nil

    init(session: Session, transcriber: Transcriber, writer: TranscriptWriter) {
        self.session = session
        self.transcriber = transcriber
        self.writer = writer
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
        await writer.append("Transcription worker started")

        // Однажды создаём индексатор для папки сессии
        let indexer = FileIndexer(dir: session.dir)

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
            let rawText = try await transcriber.transcribe(file: processingURL)

            // Таймкод из фактической длительности файла
            let chunkSec = (try? AVAudioFile(forReading: processingURL).durationSeconds) ?? 15.0
            let timecode = timecodeFor(index: index, chunkSeconds: chunkSec)

            // Санитайз и мусор-фильтр
            let printable = TextFilter.sanitize(rawText)
            if !TextFilter.shouldDrop(printable) {
                let line = "\(timecode) \(printable)"
                if line != lastWrittenLine {              // анти-дубль подряд
                    await writer.append(line)
                    lastWrittenLine = line
                }
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

    private func timecodeFor(index: Int, chunkSeconds: Double) -> String {
        let start = max(0.0, Double(index - 1) * chunkSeconds)
        let end = start + chunkSeconds
        func hhmmss(_ t: Double) -> String {
            let ti = Int(t)
            return String(format: "%02d:%02d:%02d", ti/3600, (ti%3600)/60, ti%60)
        }
        return "[\(hhmmss(start))-\(hhmmss(end))]"
    }
}
