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
    private var transcriptWriter: TranscriptWriter?
    
    // ID записей в БД для отката
    private var micRecordingID: NSManagedObjectID?
    private var sysRecordingID: NSManagedObjectID?
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.context = container.viewContext
    }
    
    public func startRecording(note: Note) async throws {
        // Проверка на текущую запись
        guard sessionPaths == nil else {
            throw ServiceError.alreadyRunning
        }
        
        do {
            // 1) Проверяем разрешения
            try await ensureMicrophonePermission()
            
            // 2) Создаем Whisper
            let transcriber = try await Transcriber(modelName: nil, language: "ru")
            self.transcriber = transcriber
            
            // 3) Создание директории сессии
            let paths = try SessionFS.makeSessionFolder()
            self.sessionPaths = paths
            
            // 4) Создаем записи в БД
            let (micID, sysID) = try createDBRecords(for: note, basePath: paths.root.path)
            self.micRecordingID = micID
            self.sysRecordingID = sysID
            
            // 5) Создаем TranscriptWriter
            let transcriptURL = paths.root.appendingPathComponent("transcript.txt")
            let writer = try TranscriptWriter(url: transcriptURL)
            self.transcriptWriter = writer
            await writer.append("— Recording started —")
            
            // 6) Создаем и запускаем TranscriptionManager
            let session = Session(dir: paths.root, transcriptURL: transcriptURL)
            let manager = TranscriptionManager(session: session, transcriber: transcriber, writer: writer)
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
        
        // Обновляем записи в БД
        let now = Date()
        if let micID = micRecordingID,
           let micRec = try? context.existingObject(with: micID) as? Recording {
            micRec.endedAt = now
            if let start = micRec.startedAt {
                micRec.durationSec = now.timeIntervalSince(start)
            }
            micRec.statusEnum = .done
        }
        
        if let sysID = sysRecordingID,
           let sysRec = try? context.existingObject(with: sysID) as? Recording {
            sysRec.endedAt = now
            if let start = sysRec.startedAt {
                sysRec.durationSec = now.timeIntervalSince(start)
            }
            sysRec.statusEnum = .done
        }
        
        try context.save()
        
        // Записываем в лог
        await transcriptWriter?.append("— Recording stopped —")
        
        // Очищаем состояние
        cleanupState()
    }
    
    // MARK: - Private Methods
    
    private func createDBRecords(for note: Note, basePath: String) throws -> (NSManagedObjectID, NSManagedObjectID) {
        let ctx = note.managedObjectContext ?? context

        // MIC Recording
        let micRec = Recording(context: ctx)
        micRec.id = UUID()
        micRec.startedAt = Date()
        micRec.statusEnum = .recording
        micRec.sourceEnum = .mic
        micRec.basePath = basePath
        micRec.note = note

        let micTranscript = MicTranscript(context: ctx)
        micTranscript.id = UUID()
        micTranscript.fullText = ""
        micTranscript.createdAt = Date()
        micTranscript.updatedAt = Date()
        micTranscript.recording = micRec

        // SYSTEM Recording (пока заглушка)
        let sysRec = Recording(context: ctx)
        sysRec.id = UUID()
        sysRec.startedAt = Date()
        sysRec.statusEnum = .recording
        sysRec.sourceEnum = .sys
        sysRec.basePath = basePath
        sysRec.note = note

        let sysTranscript = SystemTranscript(context: ctx)
        sysTranscript.id = UUID()
        sysTranscript.fullText = ""
        sysTranscript.createdAt = Date()
        sysTranscript.updatedAt = Date()
        sysTranscript.recording = sysRec

        // Помечаем саммари как устаревшее
        note.summaryStatusEnum = .pending
        note.summaryUpdatedAt = nil

        try ctx.save()
        return (micRec.objectID, sysRec.objectID)
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
        var idsToDelete: [NSManagedObjectID] = []
        if let micID = micRecordingID { idsToDelete.append(micID) }
        if let sysID = sysRecordingID { idsToDelete.append(sysID) }
        
        if !idsToDelete.isEmpty {
            try? deleteRecords(idsToDelete)
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
        transcriptWriter = nil
        sessionPaths = nil
        micRecordingID = nil
        sysRecordingID = nil
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

// MARK: - Session Helper

private struct Session {
    let dir: URL
    let transcriptURL: URL
}
