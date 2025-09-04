import Foundation
import AVFoundation

final class MicrophoneRecorder: NSObject, AVAudioRecorderDelegate {
    // Текущий и следующий рекордер (A/B)
    private var recorder: AVAudioRecorder?
    private var nextRecorder: AVAudioRecorder?

    private var timer: DispatchSourceTimer?
    private var segmentIndex: Int = 0
    private var dirURL: URL!

    private let chunkSeconds: Double
    private let onSegment: (URL, Int) -> Void

    // Небольшое перекрытие между сегментами, чтобы не терять семплы на границе
    private let overlapMs: Int = 2000

    // targetSampleRate оставлен для совместимости, здесь не используется
    init(targetSampleRate: Double, chunkSeconds: Double, onSegment: @escaping (URL, Int) -> Void) throws {
        self.chunkSeconds = chunkSeconds
        self.onSegment = onSegment
    }

    func start(into dir: URL) throws {
        self.dirURL = dir

        // Явный запрос доступа к микрофону (гарантирует TCC-диалог)
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .audio) { ok in granted = ok; sem.signal() }
        sem.wait()
        guard granted else {
            throw NSError(domain: "MicAccess", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
        }

        // Первый сегмент
        segmentIndex = 1
        let rec = try makeRecorder(for: segmentIndex)
        guard rec.record() else {
            throw NSError(domain: "MicRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "record() failed"])
        }
        self.recorder = rec
        print("Recording → \(rec.url.lastPathComponent)")

        // Таймер ротации с минимальным джиттером
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        t.schedule(deadline: .now() + chunkSeconds, repeating: chunkSeconds, leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.rotateChunk() }
        t.resume()
        self.timer = t

        print("Mic recording started via AVAudioRecorder… chunk=\(chunkSeconds)s")
    }

    func stop() {
        // Остановить таймер
        timer?.cancel()
        timer = nil

        // Аккуратно закрыть и оформить текущий/следующий (если стартанул)
        if let next = nextRecorder {
            if next.isRecording { next.stop() }
            finalize(rec: next, index: segmentIndex + 1)
            nextRecorder = nil
        }
        if let rec = recorder {
            if rec.isRecording { rec.stop() }
            finalize(rec: rec, index: segmentIndex)
            recorder = nil
        }
        print("Mic recording stopped.")
    }

    // MARK: - Внутреннее

    private func rotateChunk() {
        guard let current = recorder else { return }

        // 1) Подготовим и запустим следующий сегмент ДО остановки текущего
        let nextIdx = segmentIndex + 1
        do {
            let next = try makeRecorder(for: nextIdx)
            guard next.record() else { throw NSError(domain: "MicRecorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "record(next) failed"]) }
            self.nextRecorder = next
            print("Recording (next) → \(next.url.lastPathComponent)")
        } catch {
            fputs("Rotate prepare error: \(error)\n", stderr)
            // Если не смогли стартануть следующий — всё равно закрываем текущий
        }

        // Небольшое перекрытие (по умолчанию 30 мс)
        if overlapMs > 0 {
            usleep(useconds_t(overlapMs * 1000))
        }

        // 2) Закрываем и оформляем текущий сегмент
        current.stop()
        finalize(rec: current, index: segmentIndex)

        // 3) Повышаем next до текущего
        if let next = nextRecorder {
            recorder = next
            segmentIndex = nextIdx
            nextRecorder = nil
        }
    }

    private func makeRecorder(for index: Int) throws -> AVAudioRecorder {
        let tmpName = String(format: "raw_segment_%06d.wav", index)
        let url = dirURL.appendingPathComponent(tmpName)
        try? FileManager.default.removeItem(at: url)

        // WAV: Linear PCM, 16-bit, mono, 44.1 kHz — максимально совместимо
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.delegate = self
        guard rec.prepareToRecord() else {
            throw NSError(domain: "MicRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "prepareToRecord failed"])
        }
        return rec
    }

    private func finalize(rec: AVAudioRecorder, index: Int) {
        let rawURL = rec.url
        let pendingName = String(format: "segment_%06d.pending.wav", index)
        let pendingURL = dirURL.appendingPathComponent(pendingName)

        do {
            if FileManager.default.fileExists(atPath: pendingURL.path) {
                try FileManager.default.removeItem(at: pendingURL)
            }
            try FileManager.default.moveItem(at: rawURL, to: pendingURL)
            print("Saved segment #\(index) → \(pendingURL.lastPathComponent)")
            onSegment(pendingURL, index)
        } catch {
            fputs("Finalize move error: \(error)\n", stderr)
        }
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        fputs("Recorder encode error: \(String(describing: error))\n", stderr)
    }
}
