import Foundation
import SwiftUI
import CoreData

@MainActor
final class SummaryViewModel: ObservableObject {
    @Published var isGenerating = false
    @Published var errorMessage: String?
    
    private let summaryService: SummaryService
    private let context: NSManagedObjectContext
    private var currentTask: Task<Void, Never>?
    
    init(context: NSManagedObjectContext) {
        self.context = context
        self.summaryService = SummaryService()
    }
    
    func generateSummary(for note: Note) {
        guard !isGenerating else {
            print("Summary generation already in progress")
            return
        }
        
        guard canGenerateSummary(for: note) else {
            errorMessage = "Нет готовых записей для создания саммари"
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        currentTask = Task {
            do {
                try await summaryService.generateSummary(for: note, context: context)
                await MainActor.run {
                    self.isGenerating = false
                    self.currentTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isGenerating = false
                    self.currentTask = nil
                    // Возвращаем статус в idle при отмене
                    note.summaryStatusEnum = .idle
                    try? self.context.save()
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.currentTask = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func cancelGeneration(for note: Note) {
        summaryService.cancelCurrentRequest()
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        errorMessage = nil
        
        // Возвращаем статус в idle
        note.summaryStatusEnum = .idle
        try? context.save()
    }
    
    func refreshStatus() {
        objectWillChange.send()
    }
    
    func canGenerateSummary(for note: Note?) -> Bool {
        return true
        
        guard let note = note else { return false }
        
        // Проверяем есть ли текст заметки
        let hasNoteContent = !(note.content?.isEmpty ?? true)
        
        // Проверяем есть ли транскрипты
        let hasTranscripts: Bool = {
            guard let recordings = note.recordings?.allObjects as? [Recording] else { return false }
            
            return recordings.contains { recording in
                recording.statusEnum == .done && (
                    (recording.micTranscript?.fullText?.isEmpty == false) ||
                    (recording.systemTranscript?.fullText?.isEmpty == false)
                )
            }
        }()
        
        // Достаточно любого из источников
        return hasNoteContent || hasTranscripts
    }
    
    func getSummaryStatus(for note: Note?) -> Note.SummaryStatus {
        return note?.summaryStatusEnum ?? .idle
    }
}
