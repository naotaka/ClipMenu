import AppKit
import Foundation

/// File-backed store for user JavaScript actions under
/// `~/Library/Application Support/ClipM/script/action/`.
enum UserActionScriptsStore {
    static var directory: URL {
        if let url = ClipStoreLocation.userActionScriptsURL {
            return url
        }
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return support.appendingPathComponent("ClipM/script/action", isDirectory: true)
    }

    static var defaultTemplate: String {
        """
        // Transform the clipboard text and return the result.
        // Available globals:
        //   clipText — String
        //   clip     — ScriptableClip
        //   ClipMenu.require('relative/path') — load a library script

        return clipText;
        """
    }

    @discardableResult
    static func ensureDirectory() throws -> URL {
        let url = directory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func isUserScript(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "js",
              ScriptFileAccess.isDescendant(url, of: directory) else { return false }
        // Directories (including the actions root) are never editable scripts.
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true
    }

    static func load(at url: URL) -> String? {
        ScriptFileAccess.readSource(at: url)
    }

    static func load(path: String) -> String? {
        load(at: URL(fileURLWithPath: path))
    }

    /// Writes `content` to a uniquely named `.js` file derived from `preferredTitle`.
    @discardableResult
    static func saveNewScript(preferredTitle: String, content: String) throws -> URL {
        try ensureDirectory()
        let url = uniqueURL(forPreferredTitle: preferredTitle)
        guard content.utf8.count <= ScriptEngine.maximumSourceBytes else { throw StoreError.scriptTooLarge }
        guard isUserScript(at: url.path) else { throw StoreError.notUserScript }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func save(at url: URL, content: String) throws {
        guard isUserScript(at: url.path) else {
            throw StoreError.notUserScript
        }
        try ensureDirectory()
        guard content.utf8.count <= ScriptEngine.maximumSourceBytes else { throw StoreError.scriptTooLarge }
        guard isUserScript(at: url.path) else { throw StoreError.notUserScript }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func delete(at url: URL) throws {
        guard isUserScript(at: url.path) else {
            throw StoreError.notUserScript
        }
        try FileManager.default.removeItem(at: url)
    }

    static func rename(at url: URL, toPreferredTitle preferredTitle: String) throws -> URL {
        guard isUserScript(at: url.path) else {
            throw StoreError.notUserScript
        }
        let destination = uniqueURL(
            forPreferredTitle: preferredTitle,
            avoiding: url
        )
        if destination.standardizedFileURL == url.standardizedFileURL {
            return url
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    static func revealInFinder() throws {
        let url = try ensureDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func uniqueURL(forPreferredTitle preferredTitle: String, avoiding existing: URL? = nil) -> URL {
        let base = sanitizedFileBaseName(preferredTitle)
        let dir = directory
        var candidate = dir.appendingPathComponent("\(base).js")
        if candidate.standardizedFileURL == existing?.standardizedFileURL {
            return candidate
        }
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path),
              candidate.standardizedFileURL != existing?.standardizedFileURL {
            candidate = dir.appendingPathComponent("\(base) \(suffix).js")
            suffix += 1
        }
        return candidate
    }

    static func title(fromScriptURL url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func sanitizedFileBaseName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Untitled Action" : cleaned
    }

    enum StoreError: LocalizedError {
        case notUserScript
        case scriptTooLarge

        var errorDescription: String? {
            switch self {
            case .notUserScript:
                return "Only JavaScript files in the ClipM user actions folder can be modified."
            case .scriptTooLarge:
                return "Action scripts must be no larger than 1 MB."
            }
        }
    }
}
