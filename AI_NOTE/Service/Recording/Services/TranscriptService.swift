import Foundation
import CoreData

actor TranscriptService {
    private let context: NSManagedObjectContext
    private let micTranscript: MicTranscript
    private let sysTranscript: SystemTranscript
    
    init(micTranscript: MicTranscript, sysTranscript: SystemTranscript, context: NSManagedObjectContext) {
        self.micTranscript = micTranscript
        self.sysTranscript = sysTranscript
        self.context = context
    }
    
    /// Добавляет сегмент транскрипта в БД
    func addSegment(text: String, startMs: Int32, endMs: Int32, index: Int32, confidence: Double = 0.0) async {
        await MainActor.run {
            let segment = TranscriptSegment(context: context)
            segment.id = UUID()
            segment.text = text
            segment.startMs = startMs
            segment.endMs = endMs
            segment.index = index
            segment.confidence = confidence
            
            let transcript = (source == .mic) ? micTranscript : sysTranscript
            segment.transcript = transcript
            
            // Обновляем полный текст
            self.updateFullText(for: transcript)
            
            // Сохраняем изменения
            do {
                try context.save()
            } catch {
                print("Failed to save transcript segment: \(error)")
            }
        }
    }
    
    /// Добавляет просто текст без временных меток (для логов)
    func appendLog(_ text: String, source: Recording.Source = .mic) async {
        let now = Date()
        let startMs = Int32(now.timeIntervalSince1970 * 1000)
        await addSegment(text: text, startMs: startMs, endMs: startMs, index: 0, source: source)
    }
    
    @MainActor
    private func updateFullText(for transcript: Transcript) {
        let segments = (transcript.segments?.allObjects as? [TranscriptSegment] ?? [])
            .sorted { $0.index < $1.index }
        
        transcript.fullText = segments.map { $0.text ?? "" }.joined(separator: " ")
        transcript.updatedAt = Date()
    }
}
