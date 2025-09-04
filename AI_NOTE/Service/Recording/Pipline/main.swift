import Foundation
import AVFoundation
import Dispatch

// ДЕРЖАТЕЛЬ ССЫЛОК (живёт всё время жизни процесса)
final class Runtime {
    static let shared = Runtime()
    var recorder: MicrophoneRecorder?
    var manager: TranscriptionManager?
    var writer: TranscriptWriter?
    var transcriber: Transcriber?
    var session: Session?
    private init() {}
}

struct App {
    func run() async {
        do {
            // вот это скорее всего не нужно, так как аргументы будут подтягиваться из другого места
            let args = CommandLine.arguments
            let baseDir = Args.value(after: "--base", in: args).map(URL.init(fileURLWithPath:))
                ?? Paths.defaultBaseDir()
            let chunkSeconds = Double(Args.value(after: "--chunk", in: args) ?? "") ?? 10
            let language = Args.value(after: "--lang", in: args) ?? "ru"
            let modelName = Args.value(after: "--model", in: args)

            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            let transcriber = try await Transcriber(modelName: modelName, language: language)
            Runtime.shared.transcriber = transcriber
            print("Whisper model ready")

            await Backfill.run(in: baseDir, transcriber: transcriber) { url in
                try TranscriptWriter(url: url)
            }

            let session = try Session.create(in: baseDir)
            Runtime.shared.session = session
            print("Session dir:", session.dir.path)

            let writer = try TranscriptWriter(url: session.transcriptURL)
            Runtime.shared.writer = writer
            await writer.append("— whisper_test_3 started —")
            
            // TODO(Где то тут нужно сделать блокер на кнопку, чтобы она не отображалась пока не отработает backfill, нужен спец статус)

            let manager = TranscriptionManager(session: session, transcriber: transcriber, writer: writer)
            Runtime.shared.manager = manager

            let recorder = try MicrophoneRecorder(
                targetSampleRate: 16_000, // игнорируется внутри AVAudioRecorder-реализации
                chunkSeconds: chunkSeconds,
                onSegment: { url, idx in
                    Task { await manager.enqueue(url: url, index: idx) }
                }
            )
            Runtime.shared.recorder = recorder

            // старт воркера
            Task.detached { await manager.run() }

            try recorder.start(into: session.dir)

            // Ctrl+C
            Signal.handleInterrupt {
                Runtime.shared.recorder?.stop()
                Task {
                    await Runtime.shared.writer?.append("— whisper_test_3 stopped —")
                    exit(0)
                }
            }
        } catch {
            fputs("Fatal error: \(error)\n", stderr)
            exit(2)
        }
    }
}

enum Args {
    static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum Signal {
    static func handleInterrupt(_ block: @escaping () -> Void) {
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        src.setEventHandler(handler: block)
        src.resume()
    }
}

// Точка входа: удерживаем процесс, а объекты держит Runtime.shared
Task { await App().run() }
dispatchMain()
