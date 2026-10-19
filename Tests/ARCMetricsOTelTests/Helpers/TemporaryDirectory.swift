import Foundation

/// A unique scratch location per test.
struct TemporaryDirectory {
    /// The unique parent. Created on demand; removed by ``remove()``.
    let parent: URL

    init() {
        parent = FileManager.default.temporaryDirectory
            .appending(path: "ARCMetricsOTelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A path inside the parent that does **not** exist yet.
    var root: URL {
        parent.appending(path: "ARCMetricsOTel", directoryHint: .isDirectory)
    }

    func createParent() throws {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
    }

    /// Regular files below `directory`, at any depth. Empty when the directory does not exist.
    static func files(in directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}
