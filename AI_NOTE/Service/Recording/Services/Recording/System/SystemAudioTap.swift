import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFAudio

/// Захватывает системный звук и (на 13.х) молча потребляет видео, чтобы не было спама в лог.
@available(macOS 13.0, *)
final class SystemAudioTap: NSObject {
    private var stream: SCStream?
    private var callback: ((AVAudioPCMBuffer) -> Void)?
    private let handlerQueue = DispatchQueue(label: "SystemAudioTap.sampleHandler")

    func start(_ onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        callback = onBuffer

        // 1) Разрешение/контент
        let content = try awaitContent()
        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioTap", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available"])
        }

        // 2) Фильтр
        let filter = SCContentFilter(display: display,
                                     excludingApplications: [],
                                     exceptingWindows: [])

        // 3) Конфигурация
        let conf = SCStreamConfiguration()
        conf.capturesAudio = true

        if #available(macOS 14.0, *) {
            // На 14+ можно явно запретить видео
            conf.excludesCurrentProcessAudio = true
        } else {
            // На 13 видео полностью не отключить — минимизируем нагрузку
            conf.width = 1
            conf.height = 1
        }

        // 4) Стрим
        let stream = SCStream(filter: filter, configuration: conf, delegate: nil)
        self.stream = stream

        // АУДИО-выход — обязателен нам
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: handlerQueue)

        // На 13.х добавляем ПУСТОЙ .screen-выход, чтобы не было ошибок "output NOT found"
        if #unavailable(macOS 14.0) {
            try? stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: handlerQueue)
        }

        stream.startCapture()
    }

    func stop() {
        guard let stream = stream else { return }
        stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .audio)
        if #unavailable(macOS 14.0) {
            try? stream.removeStreamOutput(self, type: .screen)
        }
        self.stream = nil
        self.callback = nil
    }

    // MARK: - Helpers

    private func awaitContent() throws -> SCShareableContent {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<SCShareableContent, Error>!
        SCShareableContent.getWithCompletionHandler { content, err in
            if let err { result = .failure(err) }
            else if let content { result = .success(content) }
            sem.signal()
        }
        sem.wait()
        switch result! {
        case .success(let c): return c
        case .failure(let e): throw e
        }
    }
}

// MARK: - SCStreamOutput
@available(macOS 13.0, *)
extension SystemAudioTap: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sb: CMSampleBuffer,
                of outputType: SCStreamOutputType) {

        guard CMSampleBufferDataIsReady(sb) else { return }

        switch outputType {
        case .audio:
            guard let fmtDesc = CMSampleBufferGetFormatDescription(sb),
                  let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return }

            var asbd = asbdPtr.pointee
            guard let format = AVAudioFormat(streamDescription: &asbd) else { return }

            let frames = CMSampleBufferGetNumSamples(sb)
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(frames)) else { return }
            pcm.frameLength = pcm.frameCapacity

            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sb, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
            guard status == noErr else { return }

            callback?(pcm)

        case .screen:
            // macOS 13: молча «съедаем» видео, чтобы не спамил лог.
            return

        @unknown default:
            return
        }
    }
}
