import Foundation

struct FileIndexer {
    let dir: URL

    func untranscribed() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: [.creationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        let candidates = items.filter {
            $0.pathExtension.lowercased() == "wav" && SegmentStatus.from(url: $0) == .pending
        }
        return candidates.sorted { a, b in
            SegmentFiles.index(from: a) < SegmentFiles.index(from: b)
        }
    }
}
