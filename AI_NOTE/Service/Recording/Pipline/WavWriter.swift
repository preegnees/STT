import Foundation
import AVFoundation

enum WavWriter {
    static func write(samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)!
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "WavWriter", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Alloc buffer failed"])
        }
        buffer.frameLength = frames
        let dst = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { ptr in
            dst.update(from: ptr.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
