import Foundation
import AVFoundation

enum Backfill {
    static func run(in baseDir: URL,
                    transcriber: Transcriber,
                    writerFactory: (URL) throws -> TranscriptWriter) async {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }

        let sessions = items.filter { url in
            var isDir: ObjCBool = false
            let ok = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return ok && isDir.boolValue && url.lastPathComponent.hasPrefix("call_")
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

        for dir in sessions {
            await processSession(dir: dir, transcriber: transcriber, writerFactory: writerFactory)
        }
    }

    private static func processSession(dir: URL,
                                       transcriber: Transcriber,
                                       writerFactory: (URL) throws -> TranscriptWriter) async {
        let transcriptURL = dir.appendingPathComponent("transcript.txt")
        guard let writer = try? writerFactory(transcriptURL) else { return }
        let indexer = FileIndexer(dir: dir)
        let pending = indexer.untranscribed()
        if pending.isEmpty { return }

        await writer.append("— Backfill for \(dir.lastPathComponent) —")
        for url in pending {
            let processing = SegmentFiles.processingURL(for: url)
            try? FileManager.default.moveItem(at: url, to: processing)
            do {
                let text = try await transcriber.transcribe(file: processing)
                
                let raw = text
                let printable = TextFilter.sanitize(raw)
                if TextFilter.shouldDrop(printable) {
                    // fputs("Dropped as noise (backfill): \(printable)\n", stderr)
                } else {
                    let idx = SegmentFiles.index(from: processing)
                    let dur = (try? AVAudioFile(forReading: processing).durationSeconds) ?? 15.0
                    let timecode = timecodeForIndex(idx, duration: dur)
                    await writer.append("\(timecode) \(printable)")
                }
                
                if !text.isEmpty {
                    let idx = SegmentFiles.index(from: processing)
                    let dur = (try? AVAudioFile(forReading: processing).durationSeconds) ?? 15.0
                    let timecode = timecodeForIndex(idx, duration: dur)
                    await writer.append("\(timecode) \(text)")
                }
                let done = SegmentFiles.doneURL(for: processing)
                try? FileManager.default.moveItem(at: processing, to: done)
            } catch {
                // откат на pending
                let back = URL(fileURLWithPath: processing.path.replacingOccurrences(of: ".processing.", with: ".pending."))
                try? FileManager.default.moveItem(at: processing, to: back)
            }
        }
        await writer.append("— Backfill finished —")
    }

    private static func timecodeForIndex(_ index: Int, duration: Double) -> String {
        let start = max(0.0, Double(index - 1) * duration)
        let end = start + duration
        func hhmmss(_ t: Double) -> String {
            let ti = Int(t)
            return String(format: "%02d:%02d:%02d", ti/3600, (ti%3600)/60, ti%60)
        }
        return "[\(hhmmss(start))-\(hhmmss(end))]"
    }
}
