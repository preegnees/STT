import AVFoundation

extension AVAudioFile {
    var durationSeconds: Double {
        let frames = Double(length)
        let rate = fileFormat.sampleRate
        return frames / rate
    }
}
