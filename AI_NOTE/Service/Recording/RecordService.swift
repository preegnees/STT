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
    private var transcriptionManager: TranscriptionManager?
    
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
            let manager = TranscriptionManager(
                sessionDir: paths.mic,
                transcriptService: transcriptService,
                transcriber: transcriber
            )
            self.transcriptionManager = manager
            
            // Запускаем воркер транскрипции в фоне
            Task.detached { await manager.run() }
            
            // 7) Создаем и запускаем микрофонный рекордер
            let recorder = try MicrophoneRecorder(
                targetSampleRate: 16000,
                chunkSeconds: 10.0,
                onSegment: { url, idx in
                    Task { await manager.enqueue(url: url, index: idx) }
                }
            )
            self.micRecorder = recorder
            
            try recorder.start(into: paths.mic)
            
        } catch {
            // Откат при ошибке
            await rollbackOnError()
            throw error
        }
    }
    
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
            recording.statusEnum = .done
        }
        
        try context.save()
        
        // Записываем в лог
        await transcriptService?.appendLog("— Recording stopped —")
        
        // Очищаем состояние
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

    private func deleteRecords(_ ids: [NSManagedObjectID]) throws {
        for id in ids {
            if let obj = try? context.existingObject(with: id) {
                context.delete(obj)
            }
        }
        try context.save()
    }
    
    private func rollbackOnError() async {
        // Останавливаем рекордер если запустился
        micRecorder?.stop()
        
        // Удаляем записи из БД
        if let recordingID = recordingID {
            try? deleteRecords([recordingID])
        }
        
        // Удаляем папку сессии
        if let paths = sessionPaths {
            SessionFS.removeSessionFolder(paths)
        }
        
        cleanupState()
    }
    
    private func cleanupState() {
        micRecorder = nil
        transcriber = nil
        transcriptionManager = nil
        transcriptService = nil
        sessionPaths = nil
        recordingID = nil
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
