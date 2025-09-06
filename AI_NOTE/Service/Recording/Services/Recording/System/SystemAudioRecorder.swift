import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

@available(macOS 13.0, *)
final class SystemAudioRecorder: NSObject {
    private var systemTap: SystemAudioTap?
    private var audioFile: AVAudioFile?
    private var timer: DispatchSourceTimer?
    
    private var segmentIndex: Int = 0
    private var dirURL: URL!
    
    private let chunkSeconds: Double
    private let onSegment: (URL, Int) -> Void
    
    // Формат записи
    private let recordFormat: AVAudioFormat
    
    init(targetSampleRate: Double, chunkSeconds: Double, onSegment: @escaping (URL, Int) -> Void) throws {
        self.chunkSeconds = chunkSeconds
        self.onSegment = onSegment
        
        // WAV: Linear PCM, 16-bit, mono, 44.1 kHz
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: 44100,
                                        channels: 1,
                                        interleaved: false) else {
            throw NSError(domain: "SystemAudioRecorder", code: 1)
        }
        self.recordFormat = format
        super.init()
    }
    
    func start(into dir: URL) throws {
        self.dirURL = dir
        segmentIndex = 1
        
        // Стартуем первый сегмент
        try startNewSegment()
        
        let tap = SystemAudioTap()
        self.systemTap = tap
        
        try tap.start { [weak self] buffer in
            self?.processBuffer(buffer)
        }
        
        // Таймер ротации сегментов
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        t.schedule(deadline: .now() + chunkSeconds, repeating: chunkSeconds, leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.rotateSegment() }
        t.resume()
        self.timer = t
        
        print("System audio recording started...")
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
        
        systemTap?.stop()
        systemTap = nil
        
        if let _ = audioFile {
            finalizeSegment(index: segmentIndex)
        }
        audioFile = nil
        
        print("System audio recording stopped.")
    }
    
    // MARK: - Private
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile = audioFile else { return }
        
        // Конвертируем buffer в нужный формат, если требуется
        if buffer.format.isEqual(recordFormat) {
            try? audioFile.write(from: buffer)
        } else {
            // Конвертация через AVAudioConverter
            guard let converter = AVAudioConverter(from: buffer.format, to: recordFormat) else { return }
            
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * recordFormat.sampleRate / buffer.format.sampleRate) + 1024
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordFormat, frameCapacity: capacity) else { return }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            if error == nil {
                try? audioFile.write(from: convertedBuffer)
            }
        }
    }
    
    private func startNewSegment() throws {
        let rawName = String(format: "raw_segment_%06d.wav", segmentIndex)
        let url = dirURL.appendingPathComponent(rawName)
        try? FileManager.default.removeItem(at: url)
        
        let file = try AVAudioFile(forWriting: url, settings: recordFormat.settings)
        self.audioFile = file
        print("System recording → \(url.lastPathComponent)")
    }
    
    private func rotateSegment() {
        // Закрываем текущий файл
        if let _ = audioFile {
            finalizeSegment(index: segmentIndex)
        }
        
        // Запускаем следующий
        segmentIndex += 1
        do {
            try startNewSegment()
        } catch {
            print("Failed to start next segment: \(error)")
        }
    }
    
    private func finalizeSegment(index: Int) {
        guard let file = audioFile else { return }
        
        let rawURL = file.url
        audioFile = nil // Закрываем файл
        
        let pendingName = String(format: "segment_%06d.pending.wav", index)
        let pendingURL = dirURL.appendingPathComponent(pendingName)
        
        do {
            if FileManager.default.fileExists(atPath: pendingURL.path) {
                try FileManager.default.removeItem(at: pendingURL)
            }
            try FileManager.default.moveItem(at: rawURL, to: pendingURL)
            print("System segment #\(index) → \(pendingURL.lastPathComponent)")
            onSegment(pendingURL, index)
        } catch {
            print("Finalize error: \(error)")
        }
    }
}
