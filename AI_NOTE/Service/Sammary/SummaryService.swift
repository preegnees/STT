import Foundation
import CoreData
import CryptoKit

// MARK: - API Models
struct SummaryRequest: Codable {
    let transcript: String
//    let systemPrompt: String?
//    let model: String?
//    let provider: String?
//    let as_json: Bool?
//    let temperature: Double?
//    let top_p: Double?
//    let max_tokens: Int?
    
//    enum CodingKeys: String, CodingKey {
//        case transcript, systemPrompt, model, provider
//        case as_json = "as_json"
//        case temperature, top_p, max_tokens
//    }
}

struct SummaryResponse: Codable {
    let provider: String
    let model: String
    let summary: String
    let usage: UsageInfo?
}

struct UsageInfo: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Service
class SummaryService {
    private let baseURL: String
    private let session: URLSession
    private var currentTask: URLSessionDataTask?
    
    init(baseURL: String = "http://localhost:8000") {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }
    
    func generateSummary(for note: Note, context: NSManagedObjectContext) async throws {
        // 1. Собираем транскрипт из всех записей
        let fullTranscript = collectTranscript(from: note)
        guard !fullTranscript.isEmpty else {
            throw SummaryError.emptyTranscript
        }
        
        // 2. Вычисляем хеш входных данных
        let inputsHash = calculateHash(transcript: fullTranscript, noteContent: note.content ?? "")
        
        // 3. Проверяем, нужно ли обновлять саммари
        if note.summaryInputsHash == inputsHash && note.summaryStatusEnum == .ready {
            return // Саммари актуальное
        }
        
        // 4. Обновляем статус на pending
        await MainActor.run {
            note.summaryStatusEnum = .pending
            note.summaryUpdatedAt = Date()
            try? context.save()
        }
        
        do {
            // 5. Готовим запрос
            let request = SummaryRequest(
                transcript: fullTranscript,
//                systemPrompt: "Создай краткое саммари этого транскрипта на русском языке. Выдели ключевые моменты и основные темы.",
//                model: "gpt-4",
//                provider: "openai",
//                as_json: false,
//                temperature: 0.3,
//                top_p: nil,
//                max_tokens: 1000
            )
            
            // 6. Отправляем запрос
            let response = try await sendSummaryRequest(request)
    
            print("📝 Received summary: \(response.summary)")
            print("📝 Summary length: \(response.summary.count)")
            
            // 7. Сохраняем результат
            await MainActor.run {
                note.summary = response.summary
                print("📝 Assigned to note.summary: \(note.summary ?? "nil")")
                note.summaryStatus = Note.SummaryStatus.ready.rawValue
                note.summaryInputsHash = inputsHash
                note.summaryUpdatedAt = Date()
                
                do {
                    try context.save()
                    NotificationCenter.default.post(name: .NSManagedObjectContextDidSave, object: context)
                } catch {
                    print("Failed to save summary: \(error)")
                    note.summaryStatusEnum = .failed
                    try? context.save()
                }
            }
            
        } catch {
            // Обновляем статус на failed
            await MainActor.run {
                note.summaryStatusEnum = .failed
                note.summaryUpdatedAt = Date()
                try? context.save()
            }
            throw error
        }
    }
    
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Private Methods
    
    private func collectTranscript(from note: Note) -> String {
        var fullTranscript = ""
        
        // Добавляем текст заметки
        if let noteContent = note.content, !noteContent.isEmpty {
            fullTranscript += "Текст заметки:\n\(noteContent)\n\n"
        }
        
        guard let recordings = note.recordings?.allObjects as? [Recording] else {
            return fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        for recording in recordings { // Без фильтров, наверное?
            // Микрофонный транскрипт
            if let micTranscript = recording.micTranscript,
               let micText = micTranscript.fullText, !micText.isEmpty {
                fullTranscript += "Микрофон: \(micText)\n\n"
            }
            
            // Системный транскрипт
            if let sysTranscript = recording.systemTranscript,
               let sysText = sysTranscript.fullText, !sysText.isEmpty {
                fullTranscript += "Системный звук: \(sysText)\n\n"
            }
        }
        
        return fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func calculateHash(transcript: String, noteContent: String) -> String {
        let combinedText = "\(noteContent)\n---\n\(transcript)"
        let data = combinedText.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func sendSummaryRequest(_ request: SummaryRequest) async throws -> SummaryResponse {
        guard let url = URL(string: "\(baseURL)/summary") else {
            throw SummaryError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)
        
        // Сохраняем task для возможности отмены
        let (data, response) = try await withTaskCancellationHandler {
            let task = session.dataTask(with: urlRequest)
            self.currentTask = task
            return try await session.data(for: urlRequest)
        } onCancel: {
            self.currentTask?.cancel()
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(SummaryResponse.self, from: data)
        } else {
            // Попробуем распарсить ошибку
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw SummaryError.serverError(detail)
            } else {
                throw SummaryError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
    }
}

// MARK: - Errors
enum SummaryError: LocalizedError {
    case emptyTranscript
    case invalidURL
    case invalidResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Нет транскрипта для создания саммари"
        case .invalidURL:
            return "Неверный URL сервера"
        case .invalidResponse:
            return "Неверный ответ сервера"
        case .serverError(let message):
            return "Ошибка сервера: \(message)"
        }
    }
}
