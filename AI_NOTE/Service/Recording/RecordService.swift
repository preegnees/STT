//
//  RecordService.swift
//  AI_NOTE
//
//  Created by Радмир on 04.09.2025.
//

import CoreData

class RecordService {
    /*
     Нужно создать функции включения и выключения микро и системного аудио.
     Как-то нужно получить базу данных
     */
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    
    // делаем optional, т.к. создаём позже
    private var sessionFolder: URL?
    // можно держать подпапки, если используешь mic/system раздельно
    private var micFolder: URL?
    private var systemFolder: URL?
    
    init(container: NSPersistentContainer) {
        // Тут мы должны получить контроллер (он хранит в тч контекст)
        self.container = container
        self.context = container.viewContext
    }
    
    public func startRecording(note: Note) async throws {
        
        // Проверка на текущую запись
        guard sessionFolder == nil else {
            throw ServiceError.alreadyRunning
        }
        
        // Проверка доступов
        try await ensureMicrophonePermission()
        // Тоже самое нужно сделать для системного аудио
        
        do {
            // Проверяем разрешение на запись
            try await micStartRecord()
            try await sysStartRecord()
            
            // Добавить создание вишпера
            
            // Создание директории
            let paths = try SessionFS.makeSessionFolder()
            self.sessionFolder = paths.root
            
            // Создаем запись
            var rec = Recording(context: self.context)
            rec.id = UUID()
            rec.startedAt = Date()
            rec.sourceEnum = .mic
            rec.statusEnum = .processing // вот тут должен быть стартинг статус
            rec.basePath = paths.root.path    // или paths.root.path, если без подпапок
            rec.note = note
            
            // Создать транскрипт и прочее в бд
            // еще немнего текст
            
            // Создать врайтера, чтобы сохранять транскрипт
        }
        
        
        
        
        // 1) Запрос прав на микро, потом еще нужно на Системное Аудио
        try await ensureMicrophonePermission()

        // 2) Папка, куда будет записываться аудио
//        let folder = try self.makeSessionFolder()
//        self.sessionFolder = folder

        // 3) Создаём записи в БД и сохраняем (получим objectID)
//        let (micID, sysID) = try createDBRecords(for: note, basePath: folder.path)

        // 4–5) Пытаемся запустить оба источника
//        do {
//            try await micStartRecord()     // реальный старт микрофона (или пока заглушка, но отличающаяся от system)
//            try await sysStartRecord()     // сейчас заглушка; позже — реальный рекордер системного аудио
//            // Успех: запоминаем активные ID
////            self.micRecordingID = micID
////            self.sysRecordingID = sysID
//        } catch {
//            // 7) Откат: остановить то, что успели (если нужно), удалить БД-записи и папку
//            await stopIfNeededSilently()        // если микрофон стартовал — остановим его (в заглушке может быть no-op)
//            try? deleteRecords([micID, sysID])  // удаляем из Core Data
//            try? FileManager.default.removeItem(at: folder)
//            self.sessionFolder = nil
//            throw error
//        }
    }
    
    private func createDBRecords(for note: Note, basePath: String) throws -> (NSManagedObjectID, NSManagedObjectID) {
        let ctx = note.managedObjectContext ?? context

        // MIC
        let micRec = Recording(context: ctx)
        micRec.id = UUID()
        micRec.startedAt = Date()
        micRec.statusEnum = .recording
        micRec.sourceEnum = .mic
        micRec.basePath = basePath
        micRec.note = note

        let micTr = MicTranscript(context: ctx)
        micTr.id = UUID()
        micTr.fullText = ""
        micTr.createdAt = Date()
        micTr.updatedAt = Date()
        micTr.recording = micRec

        // SYSTEM
        let sysRec = Recording(context: ctx)
        sysRec.id = UUID()
        sysRec.startedAt = Date()
        sysRec.statusEnum = .recording
        sysRec.sourceEnum = .system
        sysRec.basePath = basePath
        sysRec.note = note

        let sysTr = SystemTranscript(context: ctx)
        sysTr.id = UUID()
        sysTr.fullText = ""
        sysTr.createdAt = Date()
        sysTr.updatedAt = Date()
        sysTr.recording = sysRec

        // Саммари помечаем устаревшим
        note.summaryStatusEnum = .pending
        note.summaryUpdatedAt = nil

        try ctx.save()
        return (micRec.objectID, sysRec.objectID)
    }

    private func deleteRecords(_ ids: [NSManagedObjectID]) throws {
        let ctx = context
        for id in ids {
            if let obj = try? ctx.existingObject(with: id) {
                ctx.delete(obj)
            }
        }
        try ctx.save()
    }

    public func stopRecording() async throws {
        let ctx = context
        let now = Date()

//        if let id = micRecordingID, let rec = try? ctx.existingObject(with: id) as? Recording {
//            rec.endedAt = now
//            if let s = rec.startedAt { rec.durationSec = now.timeIntervalSince(s) }
//            rec.statusEnum = .done
//        }
//        if let id = sysRecordingID, let rec = try? ctx.existingObject(with: id) as? Recording {
//            rec.endedAt = now
//            if let s = rec.startedAt { rec.durationSec = now.timeIntervalSince(s) }
//            rec.statusEnum = .done
//        }
//        try ctx.save()
//
//        // Очистка runtime
//        micRecordingID = nil
//        sysRecordingID = nil
//        sessionFolder = nil
    }

    private func stopIfNeededSilently() async {
        // Здесь останавливаем то, что успели поднять (микрофонный рекордер и т. п.)
        // Сейчас — заглушка: ничего не делаем
    }

    private func micStartRecord() async throws {
        // Реальный запуск микрофона: подготовка рекордера/очереди
        // Пока — проверка-заглушка: имитируем успех
        return
    }

    private func sysStartRecord() async throws {
        // Пока полная заглушка — имитируем успех
        return
    }
}

extension RecordService {
    // Ошибки запуска сервиса
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
