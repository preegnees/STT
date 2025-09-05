import Foundation
import WhisperKit

actor Transcriber {
    private let pipeline: WhisperKit
    private let options: DecodingOptions

    init(modelName: String?, language: String) async throws {
        var cfg = WhisperKitConfig()
        if let m = modelName { cfg.model = m }

        if #available(macOS 13.0, *) {
            var compute = ModelComputeOptions()
            compute.audioEncoderCompute = .cpuAndNeuralEngine
            compute.textDecoderCompute  = .cpuAndNeuralEngine
            cfg.computeOptions = compute
        }

        self.pipeline = try await WhisperKit(cfg)

        var opts = DecodingOptions()
        opts.language = language
        opts.task = .transcribe
        opts.noSpeechThreshold = 0.60
        opts.temperature = 0.3
        opts.compressionRatioThreshold = 2.5
        opts.suppressBlank = true
        opts.withoutTimestamps = false
        opts.verbose = true
        self.options = opts
    }

    func transcribe(file url: URL) async throws -> String {
        let results = try await pipeline.transcribe(audioPath: url.path, decodeOptions: options)
        // Собираем текст из сегментов
//        let text = results.flatMap(\.segments).map(\.text).joined()
//            .replacingOccurrences(of: #"<\|[^>]*\|>"#, with: "", options: .regularExpression)
//            .trimmingCharacters(in: .whitespacesAndNewlines)
//        return text
        return ""
    }
}
