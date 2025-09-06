import Foundation

enum SegmentStatus: String {
    case pending
    case processing
    case done

    static func from(url: URL) -> SegmentStatus? {
        let n = url.lastPathComponent
        if n.contains(".pending.") { return .pending }
        if n.contains(".processing.") { return .processing }
        if n.contains(".done.") { return .done }
        return nil
    }
}

enum SegmentFiles {
    static func processingURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path.replacingOccurrences(of: ".pending.", with: ".processing."))
    }
    static func doneURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path.replacingOccurrences(of: ".processing.", with: ".done."))
    }
    static func index(from url: URL) -> Int {
        let base = url.deletingPathExtension().lastPathComponent // e.g. segment_000001.pending
        if let range = base.range(of: "(\\d+)", options: .regularExpression) {
            return Int(base[range]) ?? 0
        }
        return 0
    }
    static func deletingURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path.replacingOccurrences(of: ".done.", with: ".deleting."))
    }
}
