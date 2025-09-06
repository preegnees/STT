import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

@available(macOS 13.0, *)
final class SystemAudioRecorder: NSObject {
    private var systemTap: SystemAudioTap?
    private var timer: DispatchSourceTimer?
    private let bufferQueue = DispatchQueue(label: "SystemAudioRecorder.bufferQueue", qos: .userInitiated)
    
    private var segmentIndex: Int = 0
    private var dirURL: URL!
    private var accumulatedSamples: [Float] = []
    
    private let chunkSeconds: Double
    private let onSegment: (URL, Int) -> Void
    private let targetSampleRate: Double = 44100.0
    
    // Конвертер для преобразования буферов в Float32
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat
    
    init(targetSampleRate: Double, chunkSeconds: Double, onSegment: @escaping (URL, Int) -> Void) throws {
        self.chunkSeconds = chunkSeconds
        self.onSegment = onSegment
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: self.targetSampleRate,
                                        channels: 1,
                                        interleaved: false) else {
            throw NSError(domain: "SystemAudioRecorder", code: 1)
        }
        self.targetFormat = format
        super.init()
    }
    
    func start(into dir: URL) throws {
        self.dirURL = dir
        segmentIndex = 1
        accumulatedSamples.removeAll()
        
        let tap = SystemAudioTap()
        self.systemTap = tap
        
        try tap.start { [weak self] buffer in
            self?.processBuffer(buffer)
        }
        
        // Таймер для сохранения сегментов
        let t = DispatchSource.makeTimerSource(queue: bufferQueue)
        t.schedule(deadline: .now() + chunkSeconds, repeating: chunkSeconds, leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.saveAccumulatedSamples() }
        t.resume()
        self.timer = t
        
        print("System audio recording started...")
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
        
        systemTap?.stop()
        systemTap = nil
        
        // Сохраняем последние накопленные сэмплы
        bufferQueue.sync {
            if !accumulatedSamples.isEmpty {
                saveAccumulatedSamples()
            }
        }
        
        print("System audio recording stopped.")
    }
    
    // MARK: - Private
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Конвертируем в Float32 моно по образцу SystemChunker
            let samples = self.convertToFloat32Mono(buffer)
            self.accumulatedSamples.append(contentsOf: samples)
        }
    }
    
    private func convertToFloat32Mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        
        // Пересоздаем конвертер если формат входа изменился
        if lastInputFormat == nil || !buffer.format.isEqual(lastInputFormat!) {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converter?.sampleRateConverterQuality = .max
            lastInputFormat = buffer.format
        }
        
        guard let converter = converter else { return [] }
        
        // Оценим ёмкость
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }
        
        // Конвертация
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        if let e = error {
            print("Convert error: \(e)")
            return []
        }
        
        // Извлекаем сэмплы
        guard out.frameLength > 0, let chan = out.floatChannelData?[0] else { return [] }
        let count = Int(out.frameLength)
        return Array(UnsafeBufferPointer(start: chan, count: count))
    }
    
    private func saveAccumulatedSamples() {
        guard !accumulatedSamples.isEmpty else { return }
        
        let samples = accumulatedSamples
        accumulatedSamples.removeAll(keepingCapacity: true)
        
        let fileName = String(format: "segment_%06d.pending.wav", segmentIndex)
        let url = dirURL.appendingPathComponent(fileName)
        
        do {
            // Используем WavWriter как в рабочем коде
            try saveFloatSamplesToWAV(samples, to: url, sampleRate: targetSampleRate)
            print("System segment #\(segmentIndex) → \(fileName)")
            onSegment(url, segmentIndex)
            segmentIndex += 1
        } catch {
            print("Failed to save segment: \(error)")
        }
    }
    
    private func saveFloatSamplesToWAV(_ samples: [Float], to url: URL, sampleRate: Double) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: sampleRate,
                                        channels: 1,
                                        interleaved: false) else {
            throw NSError(domain: "SystemAudioRecorder", code: 1)
        }
        
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SystemAudioRecorder", code: 2)
        }
        
        buffer.frameLength = frameCount
        guard let floatData = buffer.floatChannelData else {
            throw NSError(domain: "SystemAudioRecorder", code: 3)
        }
        
        // Копируем сэмплы в буфер
        samples.withUnsafeBufferPointer { src in
            floatData[0].update(from: src.baseAddress!, count: samples.count)
        }
        
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }
}
