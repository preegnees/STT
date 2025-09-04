import Foundation

actor TranscriptWriter {
    private let url: URL
    init(url: URL) throws {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            try "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
    func append(_ text: String) async {
        let ts = ISO8601DateFormatter().string(from: .now)
        let line = "[\(ts)] \(text)\n"
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            fputs("File write error: \(error)\n", stderr)
        }
    }
}
