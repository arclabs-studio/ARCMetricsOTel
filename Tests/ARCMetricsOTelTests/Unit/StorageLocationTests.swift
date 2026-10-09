import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("StorageLocation", .tags(.unit)) struct StorageLocationTests {
    private func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    @Test("prepare creates traces and logs below a root that does not exist yet") func createsDirectories() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)

        try location.prepare()

        #expect(isDirectory(scratch.root.appending(path: "traces")))
        #expect(isDirectory(scratch.root.appending(path: "logs")))
        #expect(location.traces.lastPathComponent == "traces")
        #expect(location.logs.lastPathComponent == "logs")
    }

    @Test("prepare excludes the root from backup") func excludesFromBackup() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }

        try StorageLocation(root: scratch.root).prepare()

        let values = try scratch.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("prepare can run twice") func isIdempotent() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)

        try location.prepare()

        #expect(throws: Never.self) { try location.prepare() }
        #expect(isDirectory(location.traces))
        #expect(isDirectory(location.logs))
    }

    @Test("prepare throws when the root is a regular file") func failsOnFileRoot() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        try scratch.createParent()
        try Data("occupied".utf8).write(to: scratch.root)

        #expect(throws: (any Error).self) { try StorageLocation(root: scratch.root).prepare() }
    }

    @Test("The default root is ARCMetricsOTel inside Application Support") func defaultRoot() {
        let root = StorageLocation.defaultRoot()

        #expect(root.lastPathComponent == "ARCMetricsOTel")
        #expect(root.deletingLastPathComponent().lastPathComponent == "Application Support")
    }
}
