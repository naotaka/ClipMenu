import AppKit
import KeyboardShortcuts
import Foundation
import os
import SwiftData

// MARK: - Shortcut Names

extension KeyboardShortcuts.Name {
    /// Opens the main clipboard history + snippets menu (legacy: "ClipMenu", Cmd+Shift+V).
    static let openClipMenu = Self("openClipMenu",
                                   default: .init(.v, modifiers: [.command, .shift]))
    /// Opens the history-only view (legacy: "HistoryMenu", Cmd+Ctrl+V).
    static let openHistory  = Self("openHistory",
                                   default: .init(.v, modifiers: [.command, .control]))
    /// Opens the snippets view (legacy: "SnippetsMenu", Cmd+Shift+B).
    static let openSnippets = Self("openSnippets",
                                   default: .init(.b, modifiers: [.command, .shift]))
    /// Opens the actions menu for the most recent clip (Cmd+Shift+A).
    static let openActions = Self("openActions",
                                  default: .init(.a, modifiers: [.command, .shift]))
}

// MARK: - HotkeyService

/// Registers and unregisters global keyboard shortcuts using the
/// `KeyboardShortcuts` package.
///
/// Default key combos mirror `legacy/Source/AppController.m
/// +_defaultHotKeyCombos` (keyCode 9 = V, 11 = B; modifiers 768 = ⌘⇧,
/// 4352 = ⌘⌃).
final class HotkeyService {
    fileprivate static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "Hotkeys")
    private let popupMenu = HotkeyPopupMenuPresenter()

    func register() {
        Self.log.info("Registering global shortcuts")
        ensureDefaultShortcutsIfMissing()

        // Trigger on key-up to avoid interacting with the menu while modifier
        // keys are still held down.
        KeyboardShortcuts.onKeyUp(for: .openClipMenu) { [weak self] in self?.presentFromHotkey(name: "openClipMenu", kind: .main) }
        KeyboardShortcuts.onKeyUp(for: .openHistory)  { [weak self] in self?.presentFromHotkey(name: "openHistory", kind: .history) }
        KeyboardShortcuts.onKeyUp(for: .openSnippets) { [weak self] in self?.presentFromHotkey(name: "openSnippets", kind: .snippets) }
        KeyboardShortcuts.onKeyUp(for: .openActions)  { [weak self] in self?.presentFromHotkey(name: "openActions", kind: .actions) }
    }

    func unregister() {
        Self.log.info("Unregistering global shortcuts")
        KeyboardShortcuts.removeAllHandlers()
    }

    // MARK: - Private

    private func ensureDefaultShortcutsIfMissing() {
        let names: [KeyboardShortcuts.Name] = [.openClipMenu, .openHistory, .openSnippets, .openActions]

        for name in names {
            // KeyboardShortcuts can persist disabled shortcuts as `nil`.
            // Restore the built-in default when no active shortcut exists.
            if KeyboardShortcuts.getShortcut(for: name) == nil,
               let fallback = name.defaultShortcut {
                Self.log.notice("Restoring missing shortcut for \(name.rawValue, privacy: .public)")
                KeyboardShortcuts.setShortcut(fallback, for: name)
            }
        }
    }

    private func presentFromHotkey(name: String, kind: HotkeyMenuKind) {
        Self.log.info("Hotkey triggered: \(name, privacy: .public)")
        DispatchQueue.main.async {
            // Single hotkey UX path: always show the native popup menu.
            self.popupMenu.show(using: AppRuntime.shared, kind: kind)
        }
    }
}

private enum HotkeyMenuKind {
    case main
    case history
    case snippets
    case actions
}

private final class HotkeyPopupMenuPresenter: NSObject, NSMenuDelegate {
    private let actionTarget = HotkeyPopupActionTarget()
    private var targetAppForPaste: NSRunningApplication?
    private lazy var anchorWindow: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.alphaValue = 0.001
        window.ignoresMouseEvents = true
        window.level = .statusBar
        return window
    }()

    @MainActor
    func show(using runtime: AppRuntime, kind: HotkeyMenuKind) {
        guard let context = runtime.modelContainer?.mainContext else {
            HotkeyService.log.error("Fallback popup requested but modelContext is nil")
            return
        }

        let menu = buildMenu(runtime: runtime, context: context, kind: kind)
        actionTarget.runtime = runtime
        targetAppForPaste = currentTargetApplication()
        actionTarget.targetAppForPaste = targetAppForPaste
        menu.delegate = self

        let mouse = NSEvent.mouseLocation
        anchorWindow.setFrameOrigin(mouse)
        anchorWindow.orderFront(nil)

        if let contentView = anchorWindow.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: contentView)
        } else {
            menu.popUp(positioning: nil, at: mouse, in: nil)
        }

        anchorWindow.orderOut(nil)
        HotkeyService.log.notice("Presented fallback NSMenu popup")
    }

    func menuDidClose(_ menu: NSMenu) {
        anchorWindow.orderOut(nil)
    }

    private func currentTargetApplication() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        if frontmost.processIdentifier == NSRunningApplication.current.processIdentifier {
            return nil
        }
        return frontmost
    }

    private func buildMenu(runtime: AppRuntime, context: ModelContext, kind: HotkeyMenuKind) -> NSMenu {
        let menu = NSMenu(title: "ClipMenu")
        let settings = runtime.settings

        let fetchedClips = (try? context.fetch(FetchDescriptor<ClipEntry>(
            sortBy: [SortDescriptor(\ClipEntry.lastUsedAt, order: .reverse)]
        ))) ?? []
        let clips = Array(fetchedClips.prefix(max(settings.maxHistorySize, 0)))

        let folders = (try? context.fetch(FetchDescriptor<SnippetFolder>(
            sortBy: [SortDescriptor(\SnippetFolder.sortIndex, order: .forward)]
        ))) ?? []

        let showSnippetsInMain = kind == .main
        let showHistory = kind != .snippets && kind != .actions
        let showActionsInMain = kind == .main && settings.enableAction

        if showSnippetsInMain && settings.positionOfSnippets == 0 {
            addSnippets(to: menu, folders: folders, settings: settings)
            if showHistory { menu.addItem(.separator()) }
        }

        if kind == .snippets {
            addSnippets(to: menu, folders: folders, settings: settings)
        }

        if kind == .actions {
            addActions(to: menu, clips: clips, context: context, runtime: runtime)
        }

        if showHistory {
            addHistory(to: menu, clips: clips, settings: settings)
        }

        if showSnippetsInMain && settings.positionOfSnippets == 1 {
            if showHistory { menu.addItem(.separator()) }
            addSnippets(to: menu, folders: folders, settings: settings)
        }

        if showActionsInMain {
            menu.addItem(.separator())
            addActionsSubmenu(to: menu, clips: clips, context: context, runtime: runtime)
        }

        if showHistory && settings.showClearHistoryItem {
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History", action: #selector(HotkeyPopupActionTarget.clearHistory(_:)), keyEquivalent: "")
            clear.target = actionTarget
            clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            menu.addItem(clear)
        }

        menu.addItem(.separator())
        let editSnippets = NSMenuItem(title: "Edit Snippets…", action: #selector(HotkeyPopupActionTarget.openSnippetsEditor(_:)), keyEquivalent: "")
        editSnippets.target = actionTarget
        editSnippets.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
        menu.addItem(editSnippets)

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(HotkeyPopupActionTarget.openPreferences(_:)), keyEquivalent: "")
        prefs.target = actionTarget
        prefs.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(prefs)

        let quit = NSMenuItem(title: "Quit ClipMenu", action: #selector(HotkeyPopupActionTarget.quit(_:)), keyEquivalent: "")
        quit.target = actionTarget
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)

        return menu
    }

    private func addActionsSubmenu(to menu: NSMenu, clips: [ClipEntry], context: ModelContext, runtime: AppRuntime) {
        let actionsItem = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        actionsItem.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)

        guard let targetClip = clips.first else {
            let submenu = NSMenu(title: "Actions")
            let empty = NSMenuItem(title: "No clips available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            actionsItem.submenu = submenu
            menu.addItem(actionsItem)
            return
        }

        let roots = (try? context.fetch(FetchDescriptor<ActionNode>(
            predicate: #Predicate<ActionNode> { $0.parent == nil },
            sortBy: [SortDescriptor(\ActionNode.sortIndex)]
        ))) ?? []

            let actionMenu = ActionMenuBuilder.makeMenu(
                from: roots,
                target: targetClip,
                service: runtime.actionService,
                executionContext: .transformOnly,
                postAction: { [weak self] in
                    await self?.pasteAfterActionIfNeeded(runtime: runtime)
                }
            )
        if actionMenu.items.isEmpty {
            let submenu = NSMenu(title: "Actions")
            let empty = NSMenuItem(title: "No actions configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            actionsItem.submenu = submenu
        } else {
            actionsItem.submenu = actionMenu
        }

        menu.addItem(actionsItem)
    }

    private func addActions(to menu: NSMenu, clips: [ClipEntry], context: ModelContext, runtime: AppRuntime) {
        guard let targetClip = clips.first else {
            let empty = NSMenuItem(title: "No clips available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let titleItem = NSMenuItem(title: "Actions for Most Recent Clip", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let roots = (try? context.fetch(FetchDescriptor<ActionNode>(
            predicate: #Predicate<ActionNode> { $0.parent == nil },
            sortBy: [SortDescriptor(\ActionNode.sortIndex)]
        ))) ?? []

            let actionsMenu = ActionMenuBuilder.makeMenu(
                from: roots,
                target: targetClip,
                service: runtime.actionService,
                executionContext: .transformOnly,
                postAction: { [weak self] in
                    await self?.pasteAfterActionIfNeeded(runtime: runtime)
                }
            )
        if actionsMenu.items.isEmpty {
            let empty = NSMenuItem(title: "No actions configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        while let first = actionsMenu.items.first {
            actionsMenu.removeItem(first)
            menu.addItem(first)
        }
    }

        @MainActor
        private func pasteAfterActionIfNeeded(runtime: AppRuntime) async {
            guard runtime.settings.autoPasteAfterSelection else { return }
            targetAppForPaste?.activate(options: [])
            try? await Task.sleep(nanoseconds: 180_000_000)
            await actionTarget.pasteFromHotkeyAction()
        }
    private func addSnippets(to menu: NSMenu, folders: [SnippetFolder], settings: ClipMenuSettings) {
        let enabledFolders = folders.filter(\.isEnabled)
        guard !enabledFolders.isEmpty else { return }

        if settings.showLabelsInMenu {
            let label = NSMenuItem(title: "Snippets", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
        }

        for folder in enabledFolders {
            let snippets = folder.snippets
                .filter(\.isEnabled)
                .sorted { $0.sortIndex < $1.sortIndex }

            guard !snippets.isEmpty else { continue }

            let folderItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
            folderItem.image = NSImage(named: NSImage.folderName)
            let submenu = NSMenu(title: folder.title)
            for snippet in snippets {
                let item = NSMenuItem(title: snippet.title, action: #selector(HotkeyPopupActionTarget.selectSnippet(_:)), keyEquivalent: "")
                item.target = actionTarget
                item.representedObject = snippet
                submenu.addItem(item)
            }
            folderItem.submenu = submenu
            menu.addItem(folderItem)
        }
    }

    private func addHistory(to menu: NSMenu, clips: [ClipEntry], settings: ClipMenuSettings) {
        if settings.showLabelsInMenu {
            let label = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
        }

        let inlineCount = max(settings.numberOfItemsInline, 0)
        let perFolder = max(settings.numberOfItemsInsideFolder, 1)

        let inlineClips = inlineCount == 0 ? [] : Array(clips.prefix(inlineCount))
        let folderClips = inlineCount == 0 ? clips : Array(clips.dropFirst(inlineCount))

        for (idx, clip) in inlineClips.enumerated() {
            let itemNumber = listNumber(for: idx, settings: settings)
            let item = NSMenuItem(title: clipTitle(for: clip, settings: settings, listNumber: itemNumber),
                                  action: #selector(HotkeyPopupActionTarget.selectClip(_:)),
                                  keyEquivalent: "")
            item.target = actionTarget
            item.representedObject = clip
            if settings.numericKeyEquivalents {
                item.keyEquivalent = String(itemNumber % 10)
                item.keyEquivalentModifierMask = []
            }
            if let thumbnail = thumbnailImage(for: clip, settings: settings) {
                item.image = thumbnail
                HotkeyService.log.debug("Attached inline popup thumbnail for clip index=\(idx, privacy: .public)")
            } else if clip.imageData != nil {
                HotkeyService.log.debug("Inline popup clip has imageData but no thumbnail index=\(idx, privacy: .public) bytes=\(clip.imageData?.count ?? 0, privacy: .public)")
            }
            menu.addItem(item)
        }

        let groups = stride(from: 0, to: folderClips.count, by: perFolder).map {
            Array(folderClips[$0..<min($0 + perFolder, folderClips.count)])
        }

        for (groupIndex, group) in groups.enumerated() {
            let start = inlineCount + groupIndex * perFolder + 1
            let end = start + group.count - 1
            let folderItem = NSMenuItem(title: "\(start) - \(end)", action: nil, keyEquivalent: "")
            folderItem.image = NSImage(named: NSImage.folderName)

            let submenu = NSMenu(title: folderItem.title)
            for (idx, clip) in group.enumerated() {
                let absoluteIndex = inlineCount + groupIndex * perFolder + idx
                let itemNumber = listNumber(for: absoluteIndex, settings: settings)
                let item = NSMenuItem(title: clipTitle(for: clip, settings: settings, listNumber: itemNumber),
                                      action: #selector(HotkeyPopupActionTarget.selectClip(_:)),
                                      keyEquivalent: "")
                item.target = actionTarget
                item.representedObject = clip
                if settings.numericKeyEquivalents {
                    item.keyEquivalent = String(itemNumber % 10)
                    item.keyEquivalentModifierMask = []
                }
                if let thumbnail = thumbnailImage(for: clip, settings: settings) {
                    item.image = thumbnail
                    HotkeyService.log.debug("Attached grouped popup thumbnail group=\(groupIndex, privacy: .public) idx=\(idx, privacy: .public)")
                } else if clip.imageData != nil {
                    HotkeyService.log.debug("Grouped popup clip has imageData but no thumbnail group=\(groupIndex, privacy: .public) idx=\(idx, privacy: .public) bytes=\(clip.imageData?.count ?? 0, privacy: .public)")
                }
                submenu.addItem(item)
            }

            folderItem.submenu = submenu
            menu.addItem(folderItem)
        }
    }

    private func listNumber(for index: Int, settings: ClipMenuSettings) -> Int {
        if settings.numberingStartsAtZero {
            return index % 10
        }
        let n = index + 1
        return n > 10 ? n % 10 : n
    }

    private func clipTitle(for clip: ClipEntry, settings: ClipMenuSettings, listNumber: Int) -> String {
        let source = clip.stringValue
            ?? clip.filenames?.first
            ?? clip.urlStrings?.first
            ?? ""

        let stripped = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine: String
        if let nl = stripped.firstIndex(of: "\n") {
            firstLine = String(stripped[..<nl])
        } else {
            firstLine = stripped
        }

        let maxLen = max(settings.maxMenuItemTitleLength, 1)
        let trimmed: String
        if firstLine.count > maxLen {
            trimmed = String(firstLine.prefix(max(maxLen - 3, 0))) + "..."
        } else if firstLine.isEmpty, clip.imageData != nil {
            trimmed = "(Image)"
        } else {
            trimmed = firstLine.isEmpty ? "(binary)" : firstLine
        }

        if settings.numberedMenuItems {
            return "\(listNumber). \(trimmed)"
        }
        return trimmed
    }

    private func thumbnailImage(for clip: ClipEntry, settings: ClipMenuSettings) -> NSImage? {
        guard settings.showImageInMenu,
              let imageData = clip.imageData,
              let image = decodedImage(from: imageData)
        else {
            if clip.imageData != nil {
                HotkeyService.log.debug("Popup thumbnail decode failed bytes=\(clip.imageData?.count ?? 0, privacy: .public)")
            }
            return nil
        }

        let targetSize = NSSize(width: CGFloat(settings.thumbnailWidth),
                                height: CGFloat(settings.thumbnailHeight))
        return scaledImage(image, to: targetSize)
    }

    private func scaledImage(_ image: NSImage, to size: NSSize) -> NSImage {
        guard image.size.width > 0, image.size.height > 0,
              size.width > 0, size.height > 0 else {
            return image
        }

        let ratio = min(size.width / image.size.width, size.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let drawOrigin = NSPoint(x: (size.width - drawSize.width) / 2,
                                 y: (size.height - drawSize.height) / 2)

        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: drawOrigin, size: drawSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)
        scaled.unlockFocus()
        return scaled
    }

    private func decodedImage(from data: Data) -> NSImage? {
        if let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 {
            HotkeyService.log.debug("Popup decode via NSImage size=\(Int(image.size.width), privacy: .public)x\(Int(image.size.height), privacy: .public)")
            return image
        }

        if let rep = NSBitmapImageRep(data: data) {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            HotkeyService.log.debug("Popup decode via NSBitmapImageRep size=\(Int(rep.size.width), privacy: .public)x\(Int(rep.size.height), privacy: .public)")
            return image
        }

        HotkeyService.log.debug("Popup decode failed for image bytes=\(data.count, privacy: .public)")
        return NSImage(data: data)
    }
}

private final class HotkeyPopupActionTarget: NSObject {
    weak var runtime: AppRuntime?
    weak var targetAppForPaste: NSRunningApplication?
    private let pasteService = PasteService()

    @MainActor
    private func reactivateTargetAppIfNeeded() {
        guard let targetAppForPaste else { return }
        HotkeyService.log.debug("Re-activating target app pid=\(targetAppForPaste.processIdentifier, privacy: .public)")
        targetAppForPaste.activate(options: [])
    }

    @objc func selectClip(_ sender: NSMenuItem) {
        guard let runtime,
              let clip = sender.representedObject as? ClipEntry else { return }
        Task { @MainActor in
            reactivateTargetAppIfNeeded()
            // Allow menu interaction to settle before writing pasteboard.
            try? await Task.sleep(nanoseconds: 160_000_000)
            await runtime.clipsService.select(clip, pasteImmediately: false)
            if runtime.settings.autoPasteAfterSelection {
                // Extra delay helps ensure front app is active before Cmd+V.
                try? await Task.sleep(nanoseconds: 180_000_000)
                await pasteService.paste()
            }
        }
    }

    @objc func selectSnippet(_ sender: NSMenuItem) {
        guard let runtime,
              let snippet = sender.representedObject as? Snippet else { return }
        Task { @MainActor in
            reactivateTargetAppIfNeeded()
            try? await Task.sleep(nanoseconds: 160_000_000)
            await runtime.clipsService.copyStringToPasteboard(snippet.content, pasteImmediately: false)
            if runtime.settings.autoPasteAfterSelection {
                try? await Task.sleep(nanoseconds: 180_000_000)
                await pasteService.paste()
            }
        }
    }

    @objc func clearHistory(_ sender: NSMenuItem) {
        guard let runtime else { return }
        Task { try? await runtime.clipsService.clearAll() }
    }

    @objc func openPreferences(_ sender: NSMenuItem) {
        guard let runtime else { return }
        Task { @MainActor in
            runtime.showPreferences()
        }
    }

    @objc func openSnippetsEditor(_ sender: NSMenuItem) {
        guard let runtime else { return }
        Task { @MainActor in
            runtime.showPreferences(tab: .snippets)
        }
    }

    @objc func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @MainActor
    func pasteFromHotkeyAction() async {
        await pasteService.paste()
    }
}
