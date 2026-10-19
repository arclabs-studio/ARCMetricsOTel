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

    // MARK: purge

    @Test("purge removes the buffered files and both directories") func purgeRemovesBuffer() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()
        try Data("span".utf8).write(to: location.traces.appending(path: "batch-1"))
        try Data("log".utf8).write(to: location.logs.appending(path: "batch-2"))

        try location.purge()

        #expect(!FileManager.default.fileExists(atPath: location.traces.path))
        #expect(!FileManager.default.fileExists(atPath: location.logs.path))
        #expect(TemporaryDirectory.files(in: scratch.root).isEmpty)
    }

    @Test("purge leaves everything else under the root alone") func purgeKeepsOtherFiles() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()
        let other = scratch.root.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: other)

        try location.purge()

        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(isDirectory(scratch.root))
    }

    @Test("purge does nothing when the root does not exist") func purgeWithoutRoot() {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }

        #expect(throws: Never.self) { try StorageLocation(root: scratch.root).purge() }
        #expect(!FileManager.default.fileExists(atPath: scratch.root.path))
    }

    @Test("purge removes the logs directory even when traces is already gone") func purgeWithOneDirectory() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()
        try FileManager.default.removeItem(at: location.traces)

        try location.purge()

        #expect(!FileManager.default.fileExists(atPath: location.logs.path))
    }

    @Test("purge can run twice") func purgeIsIdempotent() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()

        try location.purge()

        #expect(throws: Never.self) { try location.purge() }
    }

    @Test("purge throws when a directory cannot be removed, and the directory stays")
    func purgeThrowsWhenRemovalFails() throws {
        let scratch = TemporaryDirectory()
        let manager = FileManager.default
        defer {
            try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scratch.root.path)
            scratch.remove()
        }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()
        let file = location.traces.appending(path: "batch-1")
        try Data("span".utf8).write(to: file)
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: scratch.root.path)

        #expect(throws: (any Error).self) { try location.purge() }
        #expect(manager.fileExists(atPath: location.traces.path))
    }

    // MARK: removeBufferedFiles

    @Test("removeBufferedFiles removes every regular file in both directories, whatever its name, and keeps them")
    func removesFilesKeepsDirectories() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()
        for name in ["1700000000000", "leftover", ".hidden", "batch.tmp"] {
            try Data("x".utf8).write(to: location.traces.appending(path: name))
            try Data("y".utf8).write(to: location.logs.appending(path: name))
        }

        try location.removeBufferedFiles()

        #expect(TemporaryDirectory.files(in: location.traces).isEmpty)
        #expect(TemporaryDirectory.files(in: location.logs).isEmpty)
        #expect(isDirectory(location.traces))
        #expect(isDirectory(location.logs))
    }

    @Test("removeBufferedFiles leaves other files under the root alone") func removeKeepsOtherFiles() throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)
        try location.prepare()
        let other = scratch.root.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: other)

        try location.removeBufferedFiles()

        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test("removeBufferedFiles does nothing, and creates nothing, when the directories are absent")
    func removeWithoutDirectories() {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let location = StorageLocation(root: scratch.root)

        #expect(throws: Never.self) { try location.removeBufferedFiles() }
        #expect(!FileManager.default.fileExists(atPath: location.traces.path))
        #expect(!FileManager.default.fileExists(atPath: location.logs.path))
    }

    @Test("removeBufferedFiles throws when a file cannot be removed") func removeThrowsWhenFileIsLocked() throws {
        let scratch = TemporaryDirectory()
        let manager = FileManager.default
        let location = StorageLocation(root: scratch.root)
        let locked = location.traces.appending(path: "locked")
        defer {
            try? manager.setAttributes([.immutable: false], ofItemAtPath: locked.path)
            scratch.remove()
        }
        try location.prepare()
        try Data("x".utf8).write(to: locked)
        try manager.setAttributes([.immutable: true], ofItemAtPath: locked.path)

        #expect(throws: (any Error).self) { try location.removeBufferedFiles() }
        #expect(manager.fileExists(atPath: locked.path))
    }
}
