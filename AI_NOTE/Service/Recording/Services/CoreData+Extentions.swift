//
//  CoreData+Enums.swift
//  AI_NOTE
//
//  Created by Радмир on 04.09.2025.
//

import Foundation
import CoreData

extension Recording {
     enum Status: Int16 {
        case recording = 0     // идёт запись
        case processing = 1    // запись остановлена, но очередь сегментов ещё дорешивается
        case done = 2          // всё готово
        case failed = 3        // ошибка
    }
    
    /*
     Объяснение как это работает
     Геттер - когда мы получаем генерируется объект Source, который инициализируется значением (source это число), по этому значению в enum ищется ключ = .mic / sys
     Сеттер - когда вы присваимваем sourceEnum = .mic / sys - то мы присваиваем число source (оно сохраняется в бд, это сеттер по сути для поля source), а в sourceEnum = .mic
     
     Swift автоматически создаёт для такого enum инициализатор (для source) init?(rawValue: Int16)
     */
    var statusEnum: Status {
        get { Status(rawValue: status) ?? .recording }
        set { status = newValue.rawValue }
    }
}

extension Note {
    // Енам для статусов записи
    enum SummaryStatus: Int16 {
        case idle = 0
        case pending = 1
        case ready = 2
        case failed = 3
    }
    
    // по аналогии пишем геттеры и сеттеры
    var summaryStatusEnum: SummaryStatus {
        get { SummaryStatus(rawValue: summaryStatus) ?? .idle }
        set { summaryStatus = newValue.rawValue }
    }
}

extension Transcript {
    var sourceType: Int16 {
        if self is MicTranscript { return 0 }
        if self is SystemTranscript { return 1 }
        return 0
    }
    
    @MainActor
    func addSegment(text: String, startMs: Int32, endMs: Int32, index: Int32, confidence: Double = 0.0, context: NSManagedObjectContext, source: TranscriptSegment.Source) {
        let segment = TranscriptSegment(context: context)
        segment.id = UUID()
        segment.text = text
        segment.startMs = startMs
        segment.endMs = endMs
        segment.index = index
        segment.confidence = confidence
        segment.source = source.rawValue
        segment.transcript = self
        
        updateFullText()
        self.updatedAt = Date()
        
        do {
            try context.save()
        } catch {
            print("Failed to save transcript segment: \(error)")
        }
    }
    
    @MainActor
    private func updateFullText() {
        let segments = (segments?.allObjects as? [TranscriptSegment] ?? [])
            .sorted { $0.index < $1.index }
        fullText = segments.map { $0.text ?? "" }.joined(separator: " ")
    }
}

extension TranscriptSegment {
    enum Source: Int16 {
        case mic = 0
        case system = 1
    }
    
    var sourceEnum: Source {
        get { Source(rawValue: source) ?? .mic }
        set { source = newValue.rawValue }
    }
}
