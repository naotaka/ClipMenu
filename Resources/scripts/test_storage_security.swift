import Foundation
import AppKit
import SQLite3
import SwiftData
import Darwin

@main
struct StorageSecuritySmoke {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func mustReject(_ body: () throws -> Void) {
        do { try body(); fatalError("Unsafe store path was accepted") } catch {}
    }

    static func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("clipm-storage-security-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let support = root.appendingPathComponent("fresh")
        let store = try ClipStoreLocation.prepareURL(in: support)
        // Direct builds use the login Keychain. If that Keychain refuses this
        // unsigned process, exercise AES-GCM with an in-memory key instead.
        var removeKeys = false
        do {
            try StoreEncryption.bindPersistent(storeURL: store)
            removeKeys = true
        } catch let error as StoreEncryption.Failure {
            guard case .keyUnavailable = error else { throw error }
            StoreEncryption.bindEphemeral()
        }
        defer { if removeKeys { StoreEncryption.removeBoundKeys() } }
        require(try mode(store.deletingLastPathComponent()) == 0o700, "Store directory must be private")
        var tampered = try StoreEncryption.seal(ClipPayload(stringValue: "tamper-fixture"), domain: .history)
        tampered[tampered.index(before: tampered.endIndex)] ^= 0xff
        do {
            _ = try StoreEncryption.open(tampered, as: ClipPayload.self, domain: .history)
            fatalError("Tampered ciphertext was accepted")
        } catch {}
        let schema = Schema([ClipEntry.self, Snippet.self, SnippetFolder.self, ActionNode.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)
        ])
        let sample = ClipEntry()
        sample.stringValue = "Synthetic security fixture, never real clipboard data"
        container.mainContext.insert(sample)
        try container.mainContext.save()
        try ClipStoreLocation.protectStoreFiles(in: store.deletingLastPathComponent())
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: store.path + suffix)
            if fm.fileExists(atPath: file.path) {
                require(try mode(file) == 0o600, "Store files must be private")
            }
        }

        let suite = "ClipMenu.ErasureTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ClipMenuSettings(defaults: defaults)
        settings.autoPasteAfterSelection = false
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = ClipsService(settings: settings, pasteboard: board)
        service.start(context: container.mainContext)
        service.stop()
        let uniqueSecret = "SYNTHETIC-CLEAR-HISTORY-SECRET-\(UUID().uuidString)"
        sample.stringValue = uniqueSecret
        sample.types = [NSPasteboard.PasteboardType.string.rawValue]
        sample.rtfData = Data(uniqueSecret.utf8)
        sample.pdfData = Data(uniqueSecret.utf8)
        sample.imageData = Data(uniqueSecret.utf8)
        sample.filenames = [uniqueSecret]
        sample.urlStrings = [uniqueSecret]
        let keptFolder = SnippetFolder(title: "Kept folder")
        let keptSnippet = Snippet(title: "Kept snippet", content: "saved snippet fixture")
        keptSnippet.folder = keptFolder
        container.mainContext.insert(keptFolder)
        container.mainContext.insert(keptSnippet)
        let keptAction = ActionNode(title: "Kept action", isLeaf: true)
        container.mainContext.insert(keptAction)
        try container.mainContext.save()
        for file in try fm.contentsOfDirectory(at: store.deletingLastPathComponent(), includingPropertiesForKeys: nil) {
            if (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                let bytes = try Data(contentsOf: file)
                require(bytes.range(of: Data(uniqueSecret.utf8)) == nil, "History secret was written in plaintext")
                require(bytes.range(of: uniqueSecret.data(using: .utf16LittleEndian)!) == nil, "History secret was written as UTF-16")
            }
        }
        board.setString(uniqueSecret, forType: .string)
        let priorChangeCount = board.changeCount
        let priorGeneration = HistoryErasure.generation
        try await service.clearAll()
        require(try container.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 0, "History rows survived clear")
        require(board.string(forType: .string) == nil, "Current clipboard survived clear")
        require(HistoryErasure.generation != priorGeneration, "Pending actions were not invalidated")
        require(sample.stringValue == nil && sample.imageData == nil, "Retained model exposes cleared data")
        require(!(await service.select(sample, pasteImmediately: false)), "A stale selection restored cleared history")
        await service.handlePasteboardChange(board, expectedChangeCount: priorChangeCount)
        require(try container.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 0, "Stale capture restored cleared history")
        require(try container.mainContext.fetchCount(FetchDescriptor<Snippet>()) == 1, "Clearing removed a snippet")
        require(try container.mainContext.fetchCount(FetchDescriptor<ActionNode>()) == 1, "Clearing removed an action")
        if #available(macOS 15, *) {
            require(try container.mainContext.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).isEmpty,
                    "Persistent change history survived clear")
        }
        for file in try fm.contentsOfDirectory(at: store.deletingLastPathComponent(), includingPropertiesForKeys: nil) {
            if (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                let bytes = try Data(contentsOf: file)
                require(bytes.range(of: Data(uniqueSecret.utf8)) == nil, "Cleared bytes remain in live database or journal")
                require(bytes.range(of: uniqueSecret.data(using: .utf16LittleEndian)!) == nil, "Cleared UTF-16 bytes remain")
            }
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)])
        require(try reopened.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 0, "History returned on reopening")
        require(try reopened.mainContext.fetch(FetchDescriptor<Snippet>()).first?.content == "saved snippet fixture", "Snippet damaged on disk")
        let nextClip = ClipEntry()
        nextClip.stringValue = "new copy after clear"
        container.mainContext.insert(nextClip)
        try container.mainContext.save()
        require(try container.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 1, "Saving after VACUUM failed")
        try await service.clearAll()
        do {
            try HistoryErasure.compactSQLite(at: root.appendingPathComponent("missing.store"))
            fatalError("Store maintenance failure was silently ignored")
        } catch {}

        let legacy = root.appendingPathComponent("legacy")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try Data("fixture\(suffix)".utf8).write(to: legacy.appendingPathComponent("default.store" + suffix))
        }
        let relocated = try ClipStoreLocation.prepareURL(in: legacy)
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: relocated.path + suffix)
            require(try Data(contentsOf: file) == Data("fixture\(suffix)".utf8), "Migration lost a sidecar")
            require(try mode(file) == 0o600, "Migrated store must be private")
        }

        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let linked = root.appendingPathComponent("linked")
        try fm.createDirectory(at: linked, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linked.appendingPathComponent("ClipM"), withDestinationURL: outside)
        mustReject { _ = try ClipStoreLocation.prepareURL(in: linked) }
        require(try mode(outside) == 0o755, "Following link changed an unrelated directory")

        let linkedFileSupport = root.appendingPathComponent("linked-file")
        let linkedStore = try ClipStoreLocation.prepareURL(in: linkedFileSupport)
        let externalFile = outside.appendingPathComponent("fixture")
        try Data("unchanged".utf8).write(to: externalFile)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: externalFile.path)
        try fm.createSymbolicLink(at: linkedStore, withDestinationURL: externalFile)
        mustReject { _ = try ClipStoreLocation.prepareURL(in: linkedFileSupport) }
        require(try mode(externalFile) == 0o644, "Following link changed an unrelated file")
        try fm.removeItem(at: linkedStore)
        try fm.linkItem(at: externalFile, to: linkedStore)
        mustReject { _ = try ClipStoreLocation.prepareURL(in: linkedFileSupport) }
        require(try mode(externalFile) == 0o644, "Hard-linked file permissions changed")

        let aclSupport = root.appendingPathComponent("acl")
        let aclFolder = aclSupport.appendingPathComponent("ClipM")
        try fm.createDirectory(at: aclFolder, withIntermediateDirectories: true)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "everyone allow read,search", aclFolder.path]
        try chmod.run()
        chmod.waitUntilExit()
        require(chmod.terminationStatus == 0, "ACL fixture write failed")
        _ = try ClipStoreLocation.prepareURL(in: aclSupport)
        if let actualACL = acl_get_file(aclFolder.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(actualACL)) }
            var entry: acl_entry_t?
            require(acl_get_entry(actualACL, Int32(ACL_FIRST_ENTRY.rawValue), &entry) != 0, "Extended ACL grant remains")
        } else {
            require(errno == ENOENT, "ACL lookup failed unexpectedly")
        }
        print("PASS: private store/sidecars, synthetic SwiftData persistence, legacy relocation, symlink/hard-link rejection, ACL removal, live database/journal erasure, change-log erasure, clipboard clearing, stale-work rejection, reopen and retained snippets")
    }
}
