import Foundation
import Darwin

/// Live data lives in `~/Library/Application Support/ClipM`.
/// `Snippets.xml` is still read once from that folder. The old clip archive
/// and action plist are not imported.
enum ClipStoreLocation {
    static let folderName = "ClipM"
    static let storeName = "default.store"

    static var folderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static var snippetsURL: URL? {
        folderURL?.appendingPathComponent("Snippets.xml")
    }

    static var userActionScriptsURL: URL? {
        folderURL?.appendingPathComponent("script/action", isDirectory: true)
    }

    static var userScriptLibraryURL: URL? {
        folderURL?.appendingPathComponent("script/lib", isDirectory: true)
    }

    static func prepareURL(in supportDirectory: URL? = nil) throws -> URL {
        guard let support = supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = support.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try protect(folder, directory: true)
        try protectStoreFiles(in: folder)
        relocateLegacySupportFiles(from: support.appendingPathComponent("ClipMenu", isDirectory: true), into: folder)
        let destination = folder.appendingPathComponent(storeName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try moveLooseStoreIfNeeded(from: support, to: destination)
        }
        try protectStoreFiles(in: folder)
        return destination
    }

    /// Run before opening an existing store and after SwiftData creates a new
    /// one. The private parent also protects future SQLite sidecar files.
    static func protectStoreFiles(in folder: URL) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try protect(folder.appendingPathComponent(storeName + suffix), directory: false, allowMissing: true)
        }
    }

    private static func protect(_ url: URL, directory: Bool, allowMissing: Bool = false) throws {
        // Operate on the opened object, never follow an attacker-supplied link
        // or change permissions of a file outside our private directory.
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
                              | (directory ? O_DIRECTORY : 0))
        if descriptor < 0 {
            if allowMissing && errno == ENOENT { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else {
            throw CocoaError(.fileReadNoPermission)
        }
        // chmod alone leaves extended ACL grants in place on macOS.
        guard let acl = acl_init(0) else { throw CocoaError(.fileWriteNoPermission) }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_fd(descriptor, acl) == 0,
              fchmod(descriptor, directory ? 0o700 : 0o600) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    /// Moves a copied `Snippets.xml` and `script` folder from the original
    /// ClipMenu support directory. Leaves `clips.data` and `actions.plist` behind.
    private static func relocateLegacySupportFiles(from legacy: URL, into folder: URL) {
        let fileManager = FileManager.default
        guard let values = try? legacy.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              values.isSymbolicLink != true, values.isDirectory == true else { return }
        for name in ["Snippets.xml", "script"] {
            let source = legacy.appendingPathComponent(name)
            let destination = folder.appendingPathComponent(name)
            guard let values = try? source.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: source, to: destination)
        }
    }

    private static func moveLooseStoreIfNeeded(from support: URL, to destination: URL) throws {
        let source = support.appendingPathComponent(storeName)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        // Validate the entire family before moving any part of the database.
        try protectStoreFiles(in: support)
        var moved: [(URL, URL)] = []
        do {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let extra = URL(fileURLWithPath: source.path + suffix)
                guard fileManager.fileExists(atPath: extra.path) else { continue }
                let target = URL(fileURLWithPath: destination.path + suffix)
                try fileManager.moveItem(at: extra, to: target)
                moved.append((extra, target))
            }
        } catch {
            for (original, target) in moved.reversed() {
                try? fileManager.moveItem(at: target, to: original)
            }
            throw error
        }
    }
}
