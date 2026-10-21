import SwiftData
import AppKit
import Foundation
import os

enum ActionExecutionContext {
    case pasteContext
    case transformOnly

    var shouldPaste: Bool {
        self == .pasteContext
    }
}

/// Manages the action tree and dispatches script execution.
///
/// Reference: `legacy/Source/ActionController.{h,m}`,
///            `ActionNode.{h,m}`, `ActionNodeFactory.{h,m}`,
///            `BuiltInActionController.{h,m}`, `JavaScriptSupport.{h,m}`.
@MainActor
final class ActionService {

    private static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "Actions")
    private var context: ModelContext?
    private let engine = ActionScriptRunner()
    private let paste  = PasteService()

    nonisolated init() {}

    func start(context: ModelContext) async {
        self.context = context
        seedDefaultActionsIfNeeded()
    }

    /// Root-level action nodes sorted by persisted order.
    func rootActions() async -> [ActionNode] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<ActionNode>(
            predicate: #Predicate<ActionNode> { $0.parent == nil },
            sortBy: [SortDescriptor(\ActionNode.sortIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func rootActionCount() async -> Int {
        await rootActions().count
    }

    func availableActions(for entry: ClipEntry) async -> [ActionNode] {
        guard let context else { return [] }
        do {
            return try context.fetch(FetchDescriptor<ActionNode>(
                sortBy: [SortDescriptor(\ActionNode.sortIndex)]
            ))
        } catch {
            return []
        }
    }

    /// Dispatches an action node against a clip entry.
    /// The action result is inserted as a new top clipboard item and copied to
    /// pasteboard. Paste synthesis happens only in paste context.
    /// - Returns: `true` when the pasteboard was updated (or a remove completed).
    @discardableResult
    func perform(action node: ActionNode, on entry: ClipEntry, executionContext: ActionExecutionContext = .pasteContext) async -> Bool {
        // Keep SwiftData reads on the context's main actor. Only immutable
        // strings cross into the script runner, so execution cannot block menus.
        guard node.isEnabled else { return false }
        let generation = HistoryErasure.generation
        let prepared = PreparedAction(
            actionType: node.actionType,
            actionName: node.actionName?.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
            script: Self.scriptSource(inline: node.scriptContent, path: node.scriptPath),
            stringValue: entry.stringValue,
            filenames: entry.filenames
        )

        switch prepared.actionType {
        case "javaScript":
            guard let script = prepared.script else { return false }
            let resultText = await engine.run(script: script, text: prepared.stringValue)
            guard let resultText, generation == HistoryErasure.generation else { return false }
            return await replaceClipWithString(resultText, shouldPaste: executionContext.shouldPaste)

        case "builtin":
            return await performBuiltin(
                name: prepared.actionName ?? "",
                prepared: prepared,
                originalEntry: entry,
                executionContext: executionContext
            )

        default:
            return false
        }
    }

    // MARK: - Built-in actions
    // Keep in sync with legacy/Source/BuiltInActionController.m

    private struct PreparedAction: Sendable {
        var actionType: String?
        var actionName: String?
        var script: String?
        var stringValue: String?
        var filenames: [String]?
    }

    private func performBuiltin(
        name: String,
        prepared: PreparedAction,
        originalEntry: ClipEntry,
        executionContext: ActionExecutionContext
    ) async -> Bool {
        switch name {
        case "removeAction":
            guard let context, originalEntry.modelContext != nil else { return false }
            context.delete(originalEntry)
            do {
                try context.save()
                return true
            } catch {
                context.rollback()
                Self.log.error("Failed removing clip: \(error.localizedDescription, privacy: .private)")
                return false
            }

        case "pasteAsPlainText":
            guard let text = prepared.stringValue else { return false }
            return await replaceClipWithString(text, shouldPaste: executionContext.shouldPaste)

        case "pasteAsFilePath":
            guard let files = prepared.filenames, !files.isEmpty else { return false }
            let text = files.joined(separator: "\n")
            return await replaceClipWithString(text, shouldPaste: executionContext.shouldPaste)

        case "pasteAsHFSFilePath":
            guard let files = prepared.filenames, !files.isEmpty else { return false }
            let hfsPaths = files.compactMap { posixPath -> String? in
                let url = URL(fileURLWithPath: posixPath) as CFURL
                return CFURLCopyFileSystemPath(url, CFURLPathStyle(rawValue: 1)!) as String?
            }
            let text = hfsPaths.joined(separator: "\n")
            return await replaceClipWithString(text, shouldPaste: executionContext.shouldPaste)

        default:
            return false
        }
    }

    private func replaceClipWithString(_ string: String, shouldPaste: Bool) async -> Bool {
        guard let context else { return false }
        let transformed = ClipEntry()
        transformed.types = [NSPasteboard.PasteboardType.string.rawValue]
        transformed.stringValue = string
        context.insert(transformed)
        do {
            try context.save()
        } catch {
            context.rollback()
            Self.log.error("Failed saving transformed clip: \(error.localizedDescription, privacy: .private)")
        }

        let pboard = NSPasteboard.general
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        let wrotePasteboard = writeReplacingContents([item], on: pboard)

        if wrotePasteboard && shouldPaste {
            await paste.paste()
        }
        return wrotePasteboard
    }

    /// Clears, then writes. A failed write puts the previous contents back.
    private func writeReplacingContents(_ items: [NSPasteboardItem], on pboard: NSPasteboard) -> Bool {
        let backup = (pboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
        pboard.clearContents()
        if pboard.writeObjects(items) { return true }
        let restored = backup.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty {
            pboard.writeObjects(restored)
        }
        return false
    }

    // MARK: - Helpers

    /// Bundled script paths in older stores contain an absolute build/app path.
    /// Resolve their resource-relative suffix against the running app so renaming
    /// or moving the bundle does not silently disable every imported action.
    nonisolated static func scriptSource(
        inline: String?, path: String?, resourceRoot: URL? = Bundle.main.resourceURL
    ) -> String? {
        if let inline, !inline.isEmpty {
            return inline.utf8.count <= ScriptEngine.maximumSourceBytes ? inline : nil
        }
        guard let path, !path.isEmpty else { return nil }
        var relative: String?
        if let marker = path.range(of: "/Contents/Resources/", options: .backwards) {
            let suffix = String(path[marker.upperBound...])
            for prefix in ["scripts/action/", "script/action/"] where suffix.hasPrefix(prefix) {
                relative = String(suffix.dropFirst(prefix.count))
            }
        } else if !(path as NSString).isAbsolutePath {
            relative = path
            for prefix in ["scripts/action/", "script/action/", "action/"] where path.hasPrefix(prefix) {
                relative = String(path.dropFirst(prefix.count))
                break
            }
        }
        if let relative, let resourceRoot {
            guard ScriptFileAccess.isRelativeScriptPath(relative) else { return nil }
            for directory in ["scripts/action", "script/action"] {
                let root = resourceRoot.appendingPathComponent(directory)
                let url = root.appendingPathComponent(relative)
                guard ScriptFileAccess.isDescendant(url, of: root) else { continue }
                if let source = ScriptFileAccess.readSource(at: url) { return source }
            }
        }
        // Preserve external user scripts and their explicitly configured paths.
        guard (path as NSString).isAbsolutePath else { return nil }
        return ScriptFileAccess.readSource(at: URL(fileURLWithPath: path))
    }

    private func seedDefaultActionsIfNeeded() {
        guard let context else { return }

        let existingCount = (try? context.fetchCount(FetchDescriptor<ActionNode>())) ?? 0
        guard existingCount == 0 else { return }

        var roots: [ActionNode] = []

        roots.append(makeBuiltin(title: "Paste as Plain Text", name: "pasteAsPlainText", sortIndex: 0))
        roots.append(makeBuiltin(title: "Paste as File Path", name: "pasteAsFilePath", sortIndex: 1))
        roots.append(makeBuiltin(title: "Paste as HFS File Path", name: "pasteAsHFSFilePath", sortIndex: 2))
        roots.append(makeBuiltin(title: "Remove", name: "removeAction", sortIndex: 3))

        var nextSortIndex = roots.count
        for directory in scriptSearchRoots() {
            let scriptRoots = discoverActionNodes(in: directory)
            guard !scriptRoots.isEmpty else { continue }
            for node in scriptRoots {
                node.sortIndex = nextSortIndex
                nextSortIndex += 1
                roots.append(node)
            }
        }

        for node in roots {
            context.insert(node)
        }
        try? context.save()
    }

    private func makeBuiltin(title: String, name: String, sortIndex: Int) -> ActionNode {
        let node = ActionNode(title: title, isLeaf: true, sortIndex: sortIndex)
        node.actionType = "builtin"
        node.actionName = name
        return node
    }

    nonisolated private func scriptSearchRoots() -> [URL] {
        var roots: [URL] = []

        if let bundleRoot = Bundle.main.resourceURL {
            roots.append(bundleRoot.appendingPathComponent("script/action"))
            roots.append(bundleRoot.appendingPathComponent("scripts/action"))
        }

        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            roots.append(appSupport.appendingPathComponent("ClipM/script/action"))
        }

        var seen = Set<String>()
        return roots.filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func discoverActionNodes(in directory: URL, depth: Int = 0) -> [ActionNode] {
        guard depth < 16 else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sortedEntries = entries.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        var result: [ActionNode] = []
        var index = 0

        for url in sortedEntries {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]),
                  values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                let children = discoverActionNodes(in: url, depth: depth + 1)
                guard !children.isEmpty else { continue }
                let folder = ActionNode(title: url.lastPathComponent, isLeaf: false, sortIndex: index)
                index += 1
                for (childIndex, child) in children.enumerated() {
                    child.sortIndex = childIndex
                    child.parent = folder
                }
                folder.children = children
                result.append(folder)
                continue
            }

            guard values.isRegularFile == true, url.pathExtension.lowercased() == "js" else { continue }
            let node = ActionNode(
                title: url.deletingPathExtension().lastPathComponent,
                isLeaf: true,
                sortIndex: index
            )
            index += 1
            node.actionType = "javaScript"
            node.scriptPath = url.path
            result.append(node)
        }

        return result
    }
}

/// JavaScriptCore contexts are serialized independently of SwiftData/UI work.
private actor ActionScriptRunner {
    private let engine = ScriptEngine()

    func run(script: String, text: String?) -> String? {
        engine.run(script: script, clip: ScriptableClip(text: text))
    }
}
