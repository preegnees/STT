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
    private var settings: Settings

    private let service: RecordService
    private let container: NSPersistentContainer

    init(setting: Settings) {
        self.container = PersistenceController.shared.container
        self.service = RecordService(container: container)
        self.settings = setting
    }

    func start(note: Note) {
        guard status == .idle else { return }
        status = .loading

        Task {
            do {
                try await service.startRecording(note: note, settings: self.settings)
                /// MainActor.run нужен для обновление published параметров из другого потока
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
        // То есть если сейчас идет запись
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
}
