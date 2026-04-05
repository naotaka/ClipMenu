import JavaScriptCore
import Foundation
import AppKit

/// Executes JavaScript action scripts inside a `JSContext`.
///
/// Replicates the execution environment of `legacy/Source/JavaScriptSupport.m`:
/// - `clipText` global string
/// - `clip` global ScriptableClip bridge object
/// - `ClipMenu.require(relativePath)` library loader
final class ScriptEngine {

    private let context: JSContext

    init() {
        context = JSContext()!
        context.name = "ClipMenu Script Engine"
        setup()
    }

    /// Runs `script` source with `clip` injected as a global.
    /// Returns the string result, or `nil` on error / undefined result.
    func run(script: String, clip: ScriptableClip) -> String? {
        let clipText = clip.text ?? ""

        context.evaluateScript("var __scriptException = '';")
        context.setObject(clipText, forKeyedSubscript: "clipText" as NSString)
        context.setObject(clip, forKeyedSubscript: "clip" as NSString)

        let wrapped = """
        function __wrapper(clipText, clip) {
            try { \(script) } catch(e) { __scriptException = e.toString(); return; }
        }
        """
        context.evaluateScript(wrapped)

        let result = context.evaluateScript("__wrapper(clipText, clip)")

        if let exc = context.objectForKeyedSubscript("__scriptException")?.toString(),
           !exc.isEmpty {
            return nil
        }
        guard let result, !result.isUndefined, !result.isNull else { return nil }
        return result.toString()
    }

    // MARK: - Private

    private func setup() {
        context.exceptionHandler = { _, exception in
            print("[ScriptEngine] exception: \(exception?.toString() ?? "?")")
        }

        // ClipMenu.require(relativePath) — loads a lib script and returns success.
        let requireBlock: @convention(block) (String) -> Bool = { [weak self] relativePath in
            guard let self, !relativePath.isEmpty else { return false }
            guard let source = self.libSource(for: relativePath) else { return false }
            self.context.evaluateScript(source)
            return true
        }

        // ClipMenu.activate() — compatibility hook for scripts that prompt.
        let activateBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        let namespace = JSValue(newObjectIn: context)
        namespace?.setObject(requireBlock, forKeyedSubscript: "require" as NSString)
        namespace?.setObject(activateBlock, forKeyedSubscript: "activate" as NSString)
        context.setObject(namespace, forKeyedSubscript: "ClipMenu" as NSString)
    }

    private func libSource(for relativePath: String) -> String? {
        let pathsToTry: [String]
        if relativePath.lowercased().hasSuffix(".js") {
            pathsToTry = [relativePath]
        } else {
            pathsToTry = [relativePath, "\(relativePath).js"]
        }

        // Bundle resources first, then user support folder
        for path in pathsToTry {
            let bundleLegacyURL = Bundle.main.resourceURL?
                .appendingPathComponent("script/lib")
                .appendingPathComponent(path)
            let bundleModernURL = Bundle.main.resourceURL?
                .appendingPathComponent("scripts/lib")
                .appendingPathComponent(path)
            let userURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("ClipMenu/script/lib")
                .appendingPathComponent(path)

            for url in [bundleLegacyURL, bundleModernURL, userURL].compactMap({ $0 }) {
                if let source = try? String(contentsOf: url, encoding: .utf8) {
                    return source
                }
            }
        }

        return nil
    }
}
