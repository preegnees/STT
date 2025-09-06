import Foundation
import SwiftUI
import CoreData

enum RecordStatus {
    case idle
    case loading
    case recording

    var iconName: String {
        switch self {
        case .idle:
            return "record.circle"         // кнопка "начать запись"
        case .loading:
            return "hourglass"             // или можно ProgressView в UI
        case .recording:
            return "stop.circle.fill"      // кнопка "остановить запись"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .idle:
            return .primary
        case .loading:
            return .secondary
        case .recording:
            return .red
        }
    }
}

@MainActor
final class RecordViewModel: ObservableObject {
    @Published var status: RecordStatus = .idle
    @Published var errorText: String?

    private let service: RecordService
    private let container: NSPersistentContainer

    init() {
        self.container = PersistenceController.shared.container
        self.service = RecordService(container: container)
    }

    func start(note: Note) {
        guard status == .idle else { return }
        status = .loading

        Task {
            do {
                // Получаем настройки из Core Data
//                let settings = try await getOrCreateSettings()
                let settings = Settings(context: container.viewContext)
                settings.language = "ru"
                settings.modelWhisper = "openai_whisper-tiny"
                try await service.startRecording(note: note, settings: settings)
                await MainActor.run { self.status = .recording }
            } catch {
                await MainActor.run {
                    self.status = .idle
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        guard status == .recording else { return }
        status = .loading

        Task {
            do {
                try await service.stopRecording()
                await MainActor.run { self.status = .idle }
            } catch {
                await MainActor.run {
                    self.status = .idle
                    self.errorText = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func getOrCreateSettings() async throws -> Settings {
        let context = container.viewContext
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let request: NSFetchRequest<Settings> = Settings.fetchRequest()
                    let settings = try context.fetch(request).first
                    
                    if let existing = settings {
                        continuation.resume(returning: existing)
                    } else {
                        // Создаем настройки по умолчанию
                        let newSettings = Settings(context: context)
                        newSettings.language = "ru"
                        newSettings.modelWhisper = nil // будет использована модель по умолчанию
                        
                        try context.save()
                        continuation.resume(returning: newSettings)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
