import JavaScriptCore
import Foundation
import AppKit

/// Executes one JavaScript action with access to the selected clip and library scripts.
/// A context is never reused: globals, closures and prototype changes from an action
/// must not retain earlier clipboard contents or affect a later action.
final class ScriptEngine {
    static let maximumSourceBytes = 1_048_576
    static let maximumResultBytes = 16_777_216
    private let libraryRoots: [URL]

    init(libraryRoots: [URL]? = nil) {
        self.libraryRoots = libraryRoots ?? Self.defaultLibraryRoots
    }

    /// Returns the string result, or `nil` on error / undefined result.
    func run(script: String, clip: ScriptableClip) -> String? {
        guard script.utf8.count <= Self.maximumSourceBytes,
              let context = JSContext() else { return nil }
        context.name = "ClipMenu Script Engine"
        setup(context)
        let clipText = clip.text ?? ""
        context.setObject(clipText, forKeyedSubscript: "clipText" as NSString)
        context.setObject(clip, forKeyedSubscript: "clip" as NSString)

        // Pass clipboard text as a value, never interpolate it into JavaScript source.
        let wrapped = """
        (function(clipText, clip) {
            \(script)
        })
        """
        guard let function = context.evaluateScript(wrapped), context.exception == nil else { return nil }
        let result = function.call(withArguments: [clipText, clip])
        guard context.exception == nil, let result, !result.isUndefined, !result.isNull,
              let string = result.toString(), context.exception == nil,
              string.utf8.count <= Self.maximumResultBytes else { return nil }
        return string
    }

    private func setup(_ context: JSContext) {
        context.exceptionHandler = { context, exception in
            // Exceptions can contain clipboard text; never print them to system logs.
            context?.exception = exception
        }

        let roots = libraryRoots
        let requireBlock: @convention(block) (String) -> Bool = { [weak context] relativePath in
            guard let context, let source = Self.libSource(for: relativePath, roots: roots) else { return false }
            context.evaluateScript(source)
            let loaded = context.exception == nil
            context.exception = nil
            return loaded
        }
        let activateBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
        }
        let namespace = JSValue(newObjectIn: context)
        namespace?.setObject(requireBlock, forKeyedSubscript: "require" as NSString)
        namespace?.setObject(activateBlock, forKeyedSubscript: "activate" as NSString)
        context.setObject(namespace, forKeyedSubscript: "ClipMenu" as NSString)
    }

    private static var defaultLibraryRoots: [URL] {
        var roots: [URL] = []
        if let resourceRoot = Bundle.main.resourceURL {
            roots += [resourceRoot.appendingPathComponent("script/lib"),
                      resourceRoot.appendingPathComponent("scripts/lib")]
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("ClipM/script/lib"))
        }
        return roots
    }

    private static func libSource(for relativePath: String, roots: [URL]) -> String? {
        guard ScriptFileAccess.isRelativeScriptPath(relativePath) else { return nil }
        let paths = relativePath.lowercased().hasSuffix(".js") ? [relativePath] : [relativePath, "\(relativePath).js"]
        for path in paths {
            for root in roots {
                let candidate = root.appendingPathComponent(path)
                guard ScriptFileAccess.isDescendant(candidate, of: root) else { continue }
                if let source = ScriptFileAccess.readSource(at: candidate) { return source }
            }
        }
        return nil
    }
}

/// Shared checks for script file access. Resolve symlinks as well as `..` before
/// enforcing a root; checking only a textual path prefix permits escaped reads/writes.
enum ScriptFileAccess {
    static func isRelativeScriptPath(_ path: String) -> Bool {
        !path.isEmpty && !(path as NSString).isAbsolutePath && !path.contains("\0")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    static func isDescendant(_ url: URL, of root: URL) -> Bool {
        guard url.isFileURL, root.isFileURL else { return false }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(rootPath + "/")
    }

    static func readSource(at url: URL) -> String? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size <= ScriptEngine.maximumSourceBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: ScriptEngine.maximumSourceBytes + 1),
              data.count <= ScriptEngine.maximumSourceBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
