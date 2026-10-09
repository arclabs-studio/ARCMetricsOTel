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
}
