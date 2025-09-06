//
//  RecordService.swift
//  AI_NOTE
//
//  Created by Радмир on 04.09.2025.
//

import CoreData
import Foundation

class RecordService {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    
    // Состояние записи
    private var sessionPaths: SessionPaths?
    private var transcriber: Transcriber?
    private var micRecorder: MicrophoneRecorder?
    private var sysTranscriptionManager: TranscriptionManager?
    private var micTranscriptionManager: TranscriptionManager?
    
    private var activeManagers = Set<String>()
    private var completedManagers = Set<String>()
    
    // ID записи в БД для отката
    private var recordingID: NSManagedObjectID?
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.context = container.viewContext
    }
    
    public func startRecording(note: Note, settings: Settings) async throws {
        // Проверка на текущую запись
        guard sessionPaths == nil else {
            throw ServiceError.alreadyRunning
        }
                
        do {
            // 1) Проверяем разрешения
            // TODO: В будущем добавить сюда системный звук
            try await ensureMicrophonePermission()
            
            // 2) Создаем Whisper
            let transcriber = try await Transcriber(settings)
            self.transcriber = transcriber
            
            // 3) Создание директории сессии
            let paths = try SessionFS.makeSessionFolder()
            self.sessionPaths = paths
            
            // 4) Создаем записи в БД
            let (recordingID, micTranscript, sysTranscript) = try createDBRecords(for: note, basePath: paths.root.path)
            self.recordingID = recordingID
            
            // 5) Пишем в лог
            print("— Recording started —")
            
            // 6) Создаем и запускаем TranscriptionManager
            let micManager = TranscriptionManager(
                sessionDir: paths.mic,
                transcript: micTranscript,
                transcriber: transcriber,
                context: context,
                onComplete: { [weak self] in
                    Task { await self?.checkTranscriptionComplete(source: SourceName.mic.rawValue) }
                }
            )
            activeManagers.insert(SourceName.mic.rawValue)

            // System manager
            let sysManager = TranscriptionManager(
                sessionDir: paths.system,
                transcript: sysTranscript,
                transcriber: transcriber,
                context: context,
                onComplete: { [weak self] in
                    Task { await self?.checkTranscriptionComplete(source: SourceName.system.rawValue) }
                }
            )

            self.micTranscriptionManager = micManager
            self.sysTranscriptionManager = sysManager
            
            Task.detached { await micManager.run() }
            
            /// Мок для системного запуска
//            Task.detached {
//                await self.sysTranscriptionManager?.run()
//            }
            
            // 7) Создаем и запускаем микрофонный рекордер
            let recorder = try MicrophoneRecorder(
                targetSampleRate: 16000,
                chunkSeconds: 10.0,
                onSegment: { url, idx in
                    Task { await micManager.enqueue(url: url, index: idx) }
                }
            )
            self.micRecorder = recorder
            try recorder.start(into: paths.mic)

            // Тут будет SystemAudio
//            self.sysRecord =
//            try recorder.start(into: paths.mic)
        } catch {
            // Откат при ошибке
            // TODO Продолжить завтра
            await rollbackOnError()
            throw error
        }
    }
    
    // Также обновим метод stopRecording для использования cleanupState:
    public func stopRecording() async throws {
        guard sessionPaths != nil else {
            throw ServiceError.notRunning
        }
        
        // Останавливаем микрофонный рекордер
        micRecorder?.stop()
        
        // Обновляем запись в БД
        let now = Date()
        if let recordingID = recordingID,
           let recording = try? context.existingObject(with: recordingID) as? Recording {
            recording.endedAt = now
            if let start = recording.startedAt {
                recording.durationSec = now.timeIntervalSince(start)
            }
            recording.statusEnum = .processing
        }
        
        try context.save()
        
        print("— Recording stopped —")
        
        // Очищаем состояние сервиса
        // ВАЖНО: файлы сессии НЕ удаляем, так как TranscriptionManager
        // может еще дообрабатывать последние сегменты в фоне
        cleanupState()
    }
    
    // MARK: - Private Methods
    
    private func createDBRecords(for note: Note, basePath: String) throws -> (NSManagedObjectID, MicTranscript, SystemTranscript) {
        let ctx = note.managedObjectContext ?? context

        // Одна запись для обоих источников
        let recording = Recording(context: ctx)
        recording.id = UUID()
        recording.startedAt = Date()
        recording.statusEnum = .recording
        recording.basePath = basePath
        recording.note = note

        let micTranscript = MicTranscript(context: ctx)
        micTranscript.id = UUID()
        micTranscript.fullText = ""
        micTranscript.createdAt = Date()
        micTranscript.updatedAt = Date()
        recording.micTranscript = micTranscript

        let sysTranscript = SystemTranscript(context: ctx)
        sysTranscript.id = UUID()
        sysTranscript.fullText = ""
        sysTranscript.createdAt = Date()
        sysTranscript.updatedAt = Date()
        recording.systemTranscript = sysTranscript

        // Помечаем саммари как устаревшее
        note.summaryStatusEnum = .pending
        note.summaryUpdatedAt = nil

        try ctx.save()
        return (recording.objectID, micTranscript, sysTranscript)
    }
    
    // MARK: - Private Methods

    private func rollbackOnError() async {
        print("🔄 Rolling back recording session...")
        
        // 1) Останавливаем активные процессы
        micRecorder?.stop()
        
        // 2) Удаляем записи из базы данных
        if let recordingID = recordingID {
            do {
                if let recording = try? context.existingObject(with: recordingID) as? Recording {
                    context.delete(recording)
                    try context.save()
                    print("🗑️ Database records rolled back")
                }
            } catch {
                print("⚠️ Failed to rollback database: \(error.localizedDescription)")
                context.rollback()
            }
        }
        
        // 3) Удаляем папку сессии
        if let paths = sessionPaths {
            do {
                if FileManager.default.fileExists(atPath: paths.root.path) {
                    try FileManager.default.removeItem(at: paths.root)
                    print("🗑️ Session folder removed: \(paths.root.lastPathComponent)")
                }
            } catch {
                print("⚠️ Failed to remove session folder: \(error.localizedDescription)")
            }
        }
        
        // 4) Очищаем состояние
        cleanupState()
        print("✅ Recording service state cleaned up")
    }

    private func cleanupState() {
        micRecorder = nil
        
        // Останавливаем TranscriptionManager'ы
        Task { await micTranscriptionManager?.stop() }
        Task { await sysTranscriptionManager?.stop() }
        
        micTranscriptionManager = nil
        sysTranscriptionManager = nil
        transcriber = nil
        sessionPaths = nil
        recordingID = nil
        
        completedManagers.removeAll()
        activeManagers.removeAll()
    }
    
    private func checkTranscriptionComplete(source: String) async {
        guard activeManagers.contains(source) else { return }
        
        completedManagers.insert(source)
        
        // Проверяем: все ли активные менеджеры завершились
        if completedManagers == activeManagers {
            await markRecordingComplete()
            completedManagers.removeAll()
            activeManagers.removeAll()
        }
    }

    private func markRecordingComplete() async {
        guard let recordingID = recordingID,
              let recording = try? context.existingObject(with: recordingID) as? Recording else { return }
        
        recording.statusEnum = .done
        try? context.save()
        print("✅ Recording fully completed")
    }
}

// MARK: - Extensions

extension RecordService {
    enum ServiceError: LocalizedError {
        case alreadyRunning
        case notRunning
        case invalidNote
        case failedToCreateSessionFolder

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "Запись уже запущена."
            case .notRunning: return "Нет активной записи."
            case .invalidNote: return "Не удалось найти заметку/запись."
            case .failedToCreateSessionFolder: return "Не удалось создать папку сессии."
            }
        }
    }
}
