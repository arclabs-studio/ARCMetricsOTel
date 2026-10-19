import Foundation

/// The on-disk buffer: `<root>/traces` and `<root>/logs`.
///
/// The root defaults to `Application Support/ARCMetricsOTel`. ``prepare()`` creates the
/// directories, excludes the root from backup and sets
/// `FileProtectionType.completeUntilFirstUserAuthentication`, so a buffered batch can still be
/// sent from the background after the first unlock.
struct StorageLocation {
    /// The buffer root.
    let root: URL

    /// Buffered spans.
    var traces: URL {
        root.appending(path: "traces", directoryHint: .isDirectory)
    }

    /// Buffered log records.
    var logs: URL {
        root.appending(path: "logs", directoryHint: .isDirectory)
    }

    /// `Application Support/ARCMetricsOTel`.
    /// ``prepare()`` creates it, together with any missing parent.
    static func defaultRoot() -> URL {
        URL.applicationSupportDirectory.appending(path: "ARCMetricsOTel", directoryHint: .isDirectory)
    }

    /// Creates the directories and applies backup exclusion and file protection.
    func prepare() throws {
        let protection: [FileAttributeKey: Any] =
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        for directory in [traces, logs] {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: protection)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = root
        try root.setResourceValues(values)
    }

    /// Deletes the buffered spans and log records, including any left by an earlier launch.
    /// Missing directories are skipped; ``prepare()`` recreates them.
    func purge() throws {
        for directory in [traces, logs]
            where FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Deletes every regular file in both directories, whatever its name, and keeps the directories.
    /// Missing directories are skipped and not created.
    func removeBufferedFiles() throws {
        let manager = FileManager.default
        for directory in [traces, logs] where manager.fileExists(atPath: directory.path(percentEncoded: false)) {
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            for file in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                do {
                    try manager.removeItem(at: file)
                } catch {
                    // Upstream ages out and trims batches on its own queue: a file it deleted
                    // in the meantime is gone, which is all this asks for.
                    guard !manager.fileExists(atPath: file.path(percentEncoded: false)) else { throw error }
                }
            }
        }
    }
}
