import Foundation

struct Session {
    let dir: URL
    let transcriptURL: URL

    static func create(in base: URL) throws -> Session {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let dir = base.appendingPathComponent("call_\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let transcript = dir.appendingPathComponent("transcript.txt")
        if !FileManager.default.fileExists(atPath: transcript.path) {
            try "".write(to: transcript, atomically: true, encoding: .utf8)
        }
        return Session(dir: dir, transcriptURL: transcript)
    }
}

enum Paths {
    static func defaultBaseDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper_calls", isDirectory: true)
    }
}
