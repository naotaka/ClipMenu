import SwiftData
import AppKit
import Foundation

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
actor ActionService {

    private var context: ModelContext?
    private let engine = ScriptEngine()
    private let paste  = PasteService()

    func start(context: ModelContext) {
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
    func perform(action node: ActionNode, on entry: ClipEntry, executionContext: ActionExecutionContext = .pasteContext) async {
        guard node.isEnabled else { return }

        switch node.actionType {

        case "javaScript":
            guard let script = scriptSource(for: node) else { return }
            let scriptableClip = ScriptableClip(entry: entry)
            guard let resultText = engine.run(script: script, clip: scriptableClip) else { return }
            await replaceClipWithString(resultText, for: entry, shouldPaste: executionContext.shouldPaste)

        case "builtin":
            await performBuiltin(name: node.actionName ?? "", on: entry, executionContext: executionContext)

        default:
            break
        }
    }

    // MARK: - Built-in actions
    // Keep in sync with legacy/Source/BuiltInActionController.m

    private func performBuiltin(name: String, on entry: ClipEntry, executionContext: ActionExecutionContext) async {
        switch name {
        case "removeAction":
            guard let context else { return }
            await MainActor.run {
                context.delete(entry)
                try? context.save()
            }

        case "pasteAsPlainText":
            guard let text = entry.stringValue else { return }
            await replaceClipWithString(text, for: entry, shouldPaste: executionContext.shouldPaste)

        case "pasteAsFilePath":
            guard let files = entry.filenames, !files.isEmpty else { return }
            let text = files.joined(separator: "\n")
            await replaceClipWithString(text, for: entry, shouldPaste: executionContext.shouldPaste)

        case "pasteAsHFSFilePath":
            guard let files = entry.filenames, !files.isEmpty else { return }
            let hfsPaths = files.compactMap { posixPath -> String? in
                let url = URL(fileURLWithPath: posixPath) as CFURL
                return CFURLCopyFileSystemPath(url, CFURLPathStyle(rawValue: 1)!) as String?
            }
            let text = hfsPaths.joined(separator: "\n")
            await replaceClipWithString(text, for: entry, shouldPaste: executionContext.shouldPaste)

        default:
            break
        }
    }

    private func replaceClipWithString(_ string: String, for entry: ClipEntry, shouldPaste: Bool) async {
        guard let context else { return }

        await MainActor.run {
            let transformed = ClipEntry()
            transformed.types = [NSPasteboard.PasteboardType.string.rawValue]
            transformed.stringValue = string
            transformed.createdAt = .now
            transformed.lastUsedAt = .now

            context.insert(transformed)

            try? context.save()

            let pboard = NSPasteboard.general
            pboard.clearContents()
            pboard.setString(string, forType: .string)
        }

        if shouldPaste {
            await paste.paste()
        }
    }

    // MARK: - Helpers

    private func scriptSource(for node: ActionNode) -> String? {
        if let inline = node.scriptContent, !inline.isEmpty { return inline }
        if let path = node.scriptPath { return try? String(contentsOfFile: path, encoding: .utf8) }
        return nil
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

    private func scriptSearchRoots() -> [URL] {
        var roots: [URL] = []

        if let bundleRoot = Bundle.main.resourceURL {
            roots.append(bundleRoot.appendingPathComponent("script/action"))
            roots.append(bundleRoot.appendingPathComponent("scripts/action"))
        }

        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            roots.append(appSupport.appendingPathComponent("ClipMenu/script/action"))
        }

        var seen = Set<String>()
        return roots.filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func discoverActionNodes(in directory: URL) -> [ActionNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
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
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                let children = discoverActionNodes(in: url)
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

            guard url.pathExtension.lowercased() == "js" else { continue }
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
