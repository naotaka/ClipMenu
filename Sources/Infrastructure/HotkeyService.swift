import AppKit
import ApplicationServices
import KeyboardShortcuts
import Foundation
import os
import SwiftData
import SwiftUI
import CoreGraphics
import ObjectiveC

extension Notification.Name {
    static let clipMenuHighlightDidChange = Notification.Name("ClipMenu.highlightDidChange")
    static let clipMenuPreviewDidShow = Notification.Name("ClipMenu.previewDidShow")
    static let clipMenuPreviewDidHide = Notification.Name("ClipMenu.previewDidHide")
}

// MARK: - Shortcut Names

extension KeyboardShortcuts.Name {
    /// Opens the main clipboard history + snippets menu (⌥⌘V).
    static let openClipMenu = Self("openClipMenu",
                                   default: .init(.v, modifiers: [.command, .option]))
    /// Opens the history-only view (⌃⌘V).
    static let openHistory  = Self("openHistory",
                                   default: .init(.v, modifiers: [.command, .control]))
    /// Opens the snippets view (⌥⌘B).
    static let openSnippets = Self("openSnippets",
                                   default: .init(.b, modifiers: [.command, .option]))
    /// Opens the actions menu for the most recent clip (⇧⌘A).
    static let openActions = Self("openActions",
                                  default: .init(.a, modifiers: [.command, .shift]))
}

// MARK: - HotkeyService

/// Registers and unregisters global keyboard shortcuts using the
/// `KeyboardShortcuts` package.
///
/// Default key combos: ⌥⌘V, ⌃⌘V, ⌥⌘B, ⇧⌘A.
final class HotkeyService {
    fileprivate static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "Hotkeys")
    @MainActor private lazy var popupMenu = HotkeyPopupMenuPresenter()

    func register() {
        Self.log.info("Registering global shortcuts")
        ensureDefaultShortcutsIfMissing()
        if AppDistribution.usesAccessibility {
            ClipMenuFilterKeyHook.prepareAtLaunch()
            HotkeyTypeAheadCapture.prepare()
        }

        // Capture type-ahead on key-down, before the menu exists. Show the menu
        // on key-up so it does not open while the shortcut modifiers are held.
        KeyboardShortcuts.onKeyDown(for: .openClipMenu) { [weak self] in self?.armTypeAheadCapture() }
        KeyboardShortcuts.onKeyDown(for: .openHistory)  { [weak self] in self?.armTypeAheadCapture() }
        KeyboardShortcuts.onKeyDown(for: .openSnippets) { [weak self] in self?.armTypeAheadCapture() }
        KeyboardShortcuts.onKeyDown(for: .openActions)  { [weak self] in self?.armTypeAheadCapture() }
        KeyboardShortcuts.onKeyUp(for: .openClipMenu) { [weak self] in self?.presentFromHotkey(name: "openClipMenu", kind: .main) }
        KeyboardShortcuts.onKeyUp(for: .openHistory)  { [weak self] in self?.presentFromHotkey(name: "openHistory", kind: .history) }
        KeyboardShortcuts.onKeyUp(for: .openSnippets) { [weak self] in self?.presentFromHotkey(name: "openSnippets", kind: .snippets) }
        KeyboardShortcuts.onKeyUp(for: .openActions)  { [weak self] in self?.presentFromHotkey(name: "openActions", kind: .actions) }
    }

    func unregister() {
        Self.log.info("Unregistering global shortcuts")
        KeyboardShortcuts.removeAllHandlers()
    }

    @MainActor
    func makeStatusMenu(buttonMaxX: CGFloat? = nil) -> NSMenu? {
        popupMenu.statusMenu(using: AppRuntime.shared, buttonMaxX: buttonMaxX)
    }

    @MainActor
    func prepareStatusMenuPreview(_ menu: NSMenu) {
        popupMenu.prepareStatusMenuPreview(menu)
    }

    @MainActor
    func hidePreviewForActionMenu() {
        popupMenu.dismissPreview(force: true)
    }

    @MainActor
    func applyStatusMenuDirection(to menu: NSMenu) {
        // Obsolete (Native LTR layout handles text alignment beautifully alongside consistent minimumWidth locking)
    }

    @MainActor
    func statusMenu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        popupMenu.menu(menu, willHighlight: item)
    }

    @MainActor
    func statusMenuWillOpen(_ menu: NSMenu) {
        popupMenu.beginSlashKeyMonitorForOpenMenu()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--self-test-action-menu") {
            NativeActionMenuSmoke.start(menu: menu)
        }
        #endif
    }

    @MainActor
    func statusMenuDidClose(_ menu: NSMenu) {
        popupMenu.menuDidClose(menu)
    }

    @MainActor
    func presentMainMenuForTesting() {
        #if DEBUG
        let phase = ProcessInfo.processInfo.environment["CLIPMENU_ACTION_SMOKE_PHASE"]
        let kind: HotkeyMenuKind
        switch phase {
        case "footer-history": kind = .history
        case "footer-snippets": kind = .snippets
        case "footer-actions": kind = .actions
        default: kind = .main
        }
        popupMenu.show(using: AppRuntime.shared, kind: kind)
        #else
        popupMenu.show(using: AppRuntime.shared, kind: .main)
        #endif
    }

    @MainActor
    func presentStatusMenuForTesting() {
        popupMenu.showStatusMenuForTesting(using: AppRuntime.shared)
    }

    @MainActor
    func showStatusMenuPreviewForTesting(_ menu: NSMenu) {
        popupMenu.showPreviewForTesting(in: menu)
    }

    @MainActor
    func showPreviewForTesting(_ clip: ClipEntry, at point: NSPoint) {
        popupMenu.showPreviewForTesting(clip, at: point)
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

    private func armTypeAheadCapture() {
        guard AppDistribution.usesAccessibility else { return }
        HotkeyTypeAheadCapture.arm()
    }

    private func presentFromHotkey(name: String, kind: HotkeyMenuKind) {
        // Key-up is a second chance to arm, in case key-down did not run.
        // Re-arming keeps keys already captured while the menu is built.
        // The App Store build does not use the Accessibility event tap.
        if AppDistribution.usesAccessibility {
            HotkeyTypeAheadCapture.arm()
        }
        Self.log.info("Hotkey triggered: \(name, privacy: .public)")
        #if DEBUG
        fputs("[ClipMenu] hotkey: \(name)\n", stderr)
        #endif
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

private enum PreviewSide {
    case left
    case right

    var flipped: PreviewSide { self == .left ? .right : .left }
}

// MARK: - Clip / snippet menu filtering

private enum ClipMenuFilter {
    static func apply(query: String, imagesOnly: Bool, to rootMenu: NSMenu) {
        resetVisibility(in: rootMenu)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || imagesOnly else { return }
        applyRecursive(to: rootMenu, query: q, imagesOnly: imagesOnly)
        trimRedundantSeparators(in: rootMenu)
    }

    private static func resetVisibility(in menu: NSMenu) {
        for item in menu.items {
            item.isHidden = false
            if let sub = item.submenu {
                resetVisibility(in: sub)
            }
        }
    }

    private static func applyRecursive(to menu: NSMenu, query: String, imagesOnly: Bool) {
        for item in menu.items {
            if let sub = item.submenu {
                applyRecursive(to: sub, query: query, imagesOnly: imagesOnly)
                let anyVisible = sub.items.contains { !$0.isHidden && !$0.isSeparatorItem }
                item.isHidden = !anyVisible
                // Hidden siblings make AppKit disable the parent while the menu is
                // tracking, so the folder title turns gray and the submenu never opens.
                if anyVisible {
                    sub.autoenablesItems = false
                    item.isEnabled = true
                }
            } else if item.clipMenuFilterHaystack != nil {
                item.isHidden = !itemMatches(item, query: query, imagesOnly: imagesOnly)
            }
        }
    }

    private static func itemMatches(_ item: NSMenuItem, query: String, imagesOnly: Bool) -> Bool {
        if imagesOnly {
            guard let clip = item.representedObject as? ClipEntry, clip.imageData != nil else {
                return false
            }
        }
        if query.isEmpty { return true }
        guard let haystack = item.clipMenuFilterHaystack else { return !imagesOnly }
        return MenuFilterSubstring.matches(query, in: haystack)
    }

    private static func trimRedundantSeparators(in menu: NSMenu) {
        var changed = true
        while changed {
            changed = false
            var previousVisibleWasSeparator = true
            for item in menu.items {
                if item.isHidden { continue }
                if item.isSeparatorItem {
                    if previousVisibleWasSeparator {
                        item.isHidden = true
                        changed = true
                    } else {
                        previousVisibleWasSeparator = true
                    }
                } else {
                    previousVisibleWasSeparator = false
                }
            }
            if let last = menu.items.reversed().first(where: { !$0.isHidden }),
               last.isSeparatorItem {
                last.isHidden = true
                changed = true
            }
        }
    }
}

private func clipFilterHaystack(_ clip: ClipEntry) -> String {
    var parts: [String] = []
    if let s = clip.stringValue, !s.isEmpty { parts.append(s) }
    if let f = clip.filenames { parts.append(contentsOf: f) }
    if let u = clip.urlStrings { parts.append(contentsOf: u) }
    if parts.isEmpty {
        if clip.imageData != nil { parts.append("(Image)") }
        if clip.pdfData != nil { parts.append("(PDF)") }
    }
    return parts.joined(separator: " ")
}

private func snippetFilterHaystack(snippet: Snippet, folderTitle: String) -> String {
    [folderTitle, snippet.title, snippet.content].joined(separator: " ")
}

/// Search field that only accepts typing once activated (via `/`, highlight, or click).
private final class ClipMenuSearchField: NSSearchField {

    private var typingCaptureEnabled = false
    private var inactivePlaceholder: String = "Push / to search"
    private let caretOverlay = FilterCaretOverlayView(frame: .zero)
    private var caretBlinkTimer: Timer?

    var isTypingCaptureEnabledForTesting: Bool { typingCaptureEnabled }

    override var acceptsFirstResponder: Bool {
        typingCaptureEnabled
    }

    func activateForTypingFromMenuHighlight() {
        typingCaptureEnabled = true
        if let current = placeholderString, !current.isEmpty {
            inactivePlaceholder = current
        }
        // Hide placeholder while active so the insertion point reads as the prompt.
        placeholderString = ""
        applyActiveAppearance(true)

        // Focus for a real caret. Content-row highlight is suppressed while filter
        // mode is active, so this no longer jumps the menu to row 1.
        ensureInsertionPointVisible()
        // Menu field editors often fail to blink until after the first edit — keep a
        // fallback caret visible whenever filter mode is active.
        startFallbackCaret()
        realignSearchChrome()
    }

    /// After navigating with ↓ from the field, the menu owns keyboard again until filter is re-activated.
    func releaseTypingCaptureForMenuNavigation() {
        typingCaptureEnabled = false
        placeholderString = inactivePlaceholder
        applyActiveAppearance(false)
        stopFallbackCaret()
        window?.makeFirstResponder(nil)
        realignSearchChrome()
    }

    override func mouseDown(with event: NSEvent) {
        typingCaptureEnabled = true
        super.mouseDown(with: event)
        applyActiveAppearance(true)
        ensureInsertionPointVisible()
        startFallbackCaret()
        realignSearchChrome()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            applyActiveAppearance(true)
            ensureInsertionPointVisible()
            startFallbackCaret()
            realignSearchChrome()
        }
        return ok
    }

    override var stringValue: String {
        didSet {
            if typingCaptureEnabled {
                positionFallbackCaret()
            }
        }
    }

    override func layout() {
        super.layout()
        // AppKit drops the magnifying glass when the empty field editor attaches;
        // re-assert button frames every layout pass.
        (cell as? ClipMenuSearchFieldCell)?.recenterAccessoryButtons(in: bounds)
        if typingCaptureEnabled {
            positionFallbackCaret()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let searchCell = ClipMenuSearchFieldCell(textCell: "")
        searchCell.isEditable = true
        searchCell.isSelectable = true
        searchCell.isScrollable = true
        searchCell.isBezeled = true
        searchCell.bezelStyle = .roundedBezel
        searchCell.placeholderString = inactivePlaceholder
        searchCell.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        searchCell.drawsBackground = true
        searchCell.searchButtonCell?.isBordered = false
        searchCell.cancelButtonCell?.isBordered = false
        cell = searchCell

        drawsBackground = true
        textColor = .labelColor
        focusRingType = .exterior
        isBezeled = true
        bezelStyle = .roundedBezel
        applyActiveAppearance(false)

        caretOverlay.isHidden = true
        caretOverlay.wantsLayer = true
        addSubview(caretOverlay)
    }

    private func applyActiveAppearance(_ active: Bool) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if active {
            backgroundColor = dark
                ? NSColor.white.withAlphaComponent(0.14)
                : NSColor.black.withAlphaComponent(0.06)
            textColor = .labelColor
            focusRingType = .exterior
        } else {
            backgroundColor = dark
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.04)
            textColor = .labelColor
            focusRingType = .none
        }
        if let cell = cell as? NSSearchFieldCell {
            cell.drawsBackground = true
            cell.backgroundColor = backgroundColor
        }
        needsDisplay = true
    }

    private func realignSearchChrome() {
        (cell as? ClipMenuSearchFieldCell)?.recenterAccessoryButtons(in: bounds)
        needsDisplay = true
        // Field-editor attach is async relative to focus; realign again next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            (self.cell as? ClipMenuSearchFieldCell)?.recenterAccessoryButtons(in: self.bounds)
            self.needsDisplay = true
            if self.typingCaptureEnabled {
                self.positionFallbackCaret()
            }
        }
    }

    /// Installs / wakes the field editor so an empty focused field still blinks a caret.
    private func ensureInsertionPointVisible() {
        let styleCaret: () -> Void = { [weak self] in
            guard let self else { return }
            let targetWindow = self.window ?? NSApp.keyWindow
            guard let targetWindow else { return }

            // `selectText` is what actually installs the field editor for an empty field.
            if targetWindow.firstResponder !== self.currentEditor() {
                targetWindow.makeFirstResponder(self)
                self.selectText(nil)
            }

            guard let editor = (self.currentEditor() as? NSTextView)
                ?? (targetWindow.fieldEditor(true, for: self) as? NSTextView)
            else { return }

            editor.isEditable = true
            editor.isSelectable = true
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.textColor = .labelColor
            // Hide system caret — menu field editors often don't blink until after an
            // edit; our overlay caret is the reliable insertion point.
            editor.insertionPointColor = .clear
            let end = editor.string.utf16.count
            editor.setSelectedRange(NSRange(location: end, length: 0))
            editor.needsDisplay = true
        }

        styleCaret()
        DispatchQueue.main.async(execute: styleCaret)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: styleCaret)
    }

    private func startFallbackCaret() {
        positionFallbackCaret()
        caretOverlay.isHidden = false
        caretOverlay.alphaValue = 1
        caretBlinkTimer?.invalidate()
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self, self.typingCaptureEnabled else { return }
            self.caretOverlay.alphaValue = self.caretOverlay.alphaValue > 0.5 ? 0 : 1
        }
        caretBlinkTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopFallbackCaret() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        caretOverlay.isHidden = true
        caretOverlay.alphaValue = 1
    }

    fileprivate func refreshFallbackCaret() {
        guard typingCaptureEnabled else { return }
        positionFallbackCaret()
    }

    private func positionFallbackCaret() {
        let cellBounds = bounds
        let drawing = (cell as? NSSearchFieldCell)?.drawingRect(forBounds: cellBounds)
            ?? cellBounds.insetBy(dx: 28, dy: 4)
        let font = self.font ?? NSFont.menuFont(ofSize: NSFont.systemFontSize)
        let text = stringValue as NSString
        let textWidth = text.size(withAttributes: [.font: font]).width
        let caretHeight = max(font.pointSize + 2, 12)
        let x = drawing.minX + min(textWidth, max(0, drawing.width - 2))
        let y = drawing.midY - caretHeight / 2
        caretOverlay.frame = NSRect(x: x.rounded(.towardZero), y: y.rounded(.towardZero), width: 1.5, height: caretHeight)
        caretOverlay.updateColor(for: effectiveAppearance)
        if typingCaptureEnabled {
            caretOverlay.isHidden = false
        }
    }
}

/// Simple blinking insertion-point drawn above the search field (menu field editors are flaky).
private final class FilterCaretOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateColor(for appearance: NSAppearance) {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.white : NSColor.black).cgColor
    }
}

/// Keeps the magnifying glass / cancel buttons vertically centered.
/// Stock `NSSearchFieldCell` drops them when an empty field editor is attached.
private final class ClipMenuSearchFieldCell: NSSearchFieldCell {

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        verticallyCentered(super.searchButtonRect(forBounds: rect), in: rect)
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        verticallyCentered(super.cancelButtonRect(forBounds: rect), in: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        // Only inset horizontally for the search/cancel chrome. Leave AppKit's
        // vertical metrics alone — shrinking height here hid the empty-field caret.
        var drawing = super.drawingRect(forBounds: rect)
        let search = searchButtonRect(forBounds: rect)
        let cancel = cancelButtonRect(forBounds: rect)
        let left = search.maxX + 2
        let right = cancel.width > 0 ? cancel.minX - 2 : rect.maxX - 4
        drawing.origin.x = left
        drawing.size.width = max(0, right - left)
        return drawing
    }

    fileprivate func recenterAccessoryButtons(in bounds: NSRect) {
        // Drawing uses searchButtonRect(forBounds:) / cancelButtonRect(forBounds:);
        // force those paths to repaint after the field editor attaches.
        let searchRect = searchButtonRect(forBounds: bounds)
        let cancelRect = cancelButtonRect(forBounds: bounds)
        controlView?.setNeedsDisplay(searchRect.union(cancelRect))
        controlView?.needsDisplay = true
    }

    private func verticallyCentered(_ buttonRect: NSRect, in bounds: NSRect) -> NSRect {
        var centered = buttonRect
        centered.origin.y = bounds.origin.y + ((bounds.height - buttonRect.height) / 2).rounded(.towardZero)
        return centered
    }
}

/// Single menu-row filter control: search field + images toggle.
/// Clip name in the actions-shortcut menu. Drawn as a view so the text stays
/// at full label color instead of the dim color used for disabled menu titles.
private final class ActionClipIdentityView: NSView {
    init(title: String, thumbnail: NSImage?) {
        let display = title.isEmpty ? "Image" : title
        let font = NSFont.menuFont(ofSize: 13)
        let textWidth = ceil((display as NSString).size(withAttributes: [.font: font]).width)
        let thumbSize = thumbnail?.size ?? .zero
        let height = max(24, thumbSize.height + 8)
        let width = 20 + textWidth + (thumbnail == nil ? 0 : 8 + thumbSize.width) + 16
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: height))

        let label = NSTextField(labelWithString: display)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        var constraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if let thumbnail {
            let imageView = NSImageView(image: thumbnail)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            constraints += [
                label.trailingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -8),
                imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: thumbSize.width),
                imageView.heightAnchor.constraint(equalToConstant: thumbSize.height),
            ]
        } else {
            constraints.append(label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A shorter menu row than AppKit draws on its own.
///
/// System rows leave about as much empty padding as the title itself, which
/// pushes clipboard history off a menu full of snippet folders. This view
/// keeps the menu font and icons, and cuts that padding down. Thumbnails are
/// drawn here too, so inline clip numbers share one left edge with text rows.
private final class CompactMenuRowView: NSView {
    /// Menu font line box is ~16pt. 18pt keeps descenders and a 16pt folder icon.
    private static let contentHeight: CGFloat = 18
    /// Extra space between rows, on top of that content height.
    private static let rowGap: CGFloat = 2
    static var rowHeight: CGFloat { contentHeight + rowGap }

    private let fixedHeight: CGFloat

    static func install(on item: NSMenuItem) {
        guard item.view == nil, !item.isSeparatorItem else { return }

        let thumb = attachmentHeight(of: item) ?? 0
        let iconHeight = item.image?.size.height ?? 0
        let content = max(contentHeight, thumb, iconHeight)
        item.view = CompactMenuRowView(height: content + rowGap)
    }

    static func attachmentHeight(of item: NSMenuItem) -> CGFloat? {
        attachmentImage(of: item)?.size.height
    }

    static func attachmentImage(of item: NSMenuItem) -> NSImage? {
        guard let attributed = item.attributedTitle, attributed.length > 0 else { return nil }
        var image: NSImage?
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let attachment = value as? NSTextAttachment, let attached = attachment.image else { return }
            image = attached
            stop.pointee = true
        }
        return image
    }

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: fixedHeight))
    }

    override var isOpaque: Bool { false }

    /// AppKit does not invoke the action of a menu item that draws itself.
    /// A click has to perform it. Submenu rows stay with the menu so the folder can open.
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let item = enclosingMenuItem else { return }
        _ = Self.activate(item)
    }

    @discardableResult
    static func activate(_ item: NSMenuItem) -> Bool {
        guard item.isEnabled, item.submenu == nil, item.action != nil, let menu = item.menu else { return false }
        let index = menu.index(of: item)
        guard index >= 0 else { return false }
        menu.cancelTracking()
        menu.performActionForItem(at: index)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item = enclosingMenuItem else { return }
        let enabled = item.isEnabled
        let highlighted = item.isHighlighted && enabled

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let pill = bounds.insetBy(dx: 5, dy: 1)
            NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        }

        let textColor: NSColor = highlighted
            ? .selectedMenuItemTextColor
            : (enabled ? .labelColor : .disabledControlTextColor)

        var cursorX = bounds.minX + 8
        let chevronSlot: CGFloat = item.submenu == nil ? 0 : 16
        let trailing = bounds.maxX - 8 - chevronSlot
        let thumbnail = Self.attachmentImage(of: item)
        let thumbnailSize = fittedThumbnailSize(thumbnail, maxHeight: bounds.height - 2)

        if let image = item.image, image.size.width > 0, image.size.height > 0 {
            let side = min(image.size.height, bounds.height - 2)
            let width = image.size.width * (side / image.size.height)
            let iconRect = NSRect(x: cursorX, y: bounds.midY - side / 2, width: width, height: side)
            drawImage(image, in: iconRect, tint: image.isTemplate ? textColor : nil)
            cursorX = iconRect.maxX + 5
        }

        let font = item.menu?.font ?? NSFont.menuFont(ofSize: 0)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style,
        ]
        let title = item.title as NSString
        let textSize = title.size(withAttributes: attributes)
        let thumbnailSlot = thumbnailSize.width > 0 ? thumbnailSize.width + 6 : 0
        let textWidth = max(0, trailing - cursorX - thumbnailSlot)
        let textRect = NSRect(
            x: cursorX,
            y: bounds.midY - textSize.height / 2,
            width: textWidth,
            height: textSize.height
        )
        if title.length > 0 {
            title.draw(in: textRect, withAttributes: attributes)
        }

        if let thumbnail, thumbnailSize.width > 0 {
            let usedText = min(textSize.width, textWidth)
            let thumbX = title.length > 0 ? cursorX + usedText + 6 : cursorX
            let thumbRect = NSRect(
                x: thumbX,
                y: bounds.midY - thumbnailSize.height / 2,
                width: thumbnailSize.width,
                height: thumbnailSize.height
            )
            thumbnail.draw(in: thumbRect)
        }

        if item.submenu != nil,
           let symbol = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            let configured = symbol.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)) ?? symbol
            let side: CGFloat = 10
            let rect = NSRect(x: bounds.maxX - 10 - side, y: bounds.midY - side / 2, width: side, height: side)
            drawImage(configured, in: rect, tint: textColor)
        }
    }

    private func fittedThumbnailSize(_ image: NSImage?, maxHeight: CGFloat) -> NSSize {
        guard let image, image.size.width > 0, image.size.height > 0, maxHeight > 0 else { return .zero }
        let side = min(image.size.height, maxHeight)
        let width = image.size.width * (side / image.size.height)
        return NSSize(width: width, height: side)
    }

    private func drawImage(_ image: NSImage, in rect: NSRect, tint: NSColor?) {
        guard let tint else {
            image.draw(in: rect)
            return
        }
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        tint.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }
}

private final class ClipMenuFilterBarView: NSView {
    let searchField: ClipMenuSearchField
    let imagesButton: NSButton
    var onImagesFilterToggle: (() -> Void)?

    init(width: CGFloat) {
        let height: CGFloat = 36
        searchField = ClipMenuSearchField(frame: .zero)
        imagesButton = NSButton(frame: .zero)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        searchField.placeholderString = "Push / to search · Tab images"
        searchField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        searchField.setAccessibilityLabel("Push / to search, Tab for images only")
        searchField.translatesAutoresizingMaskIntoConstraints = false

        imagesButton.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Show images only")
        imagesButton.imagePosition = .imageOnly
        imagesButton.bezelStyle = .flexiblePush
        imagesButton.isBordered = true
        imagesButton.setButtonType(.pushOnPushOff)
        imagesButton.toolTip = "Show images only (Tab)"
        imagesButton.setAccessibilityLabel("Show images only")
        imagesButton.target = self
        imagesButton.action = #selector(imagesButtonClicked(_:))
        imagesButton.translatesAutoresizingMaskIntoConstraints = false
        imagesButton.setContentHuggingPriority(.required, for: .horizontal)
        imagesButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(searchField)
        addSubview(imagesButton)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 24),

            imagesButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
            imagesButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            imagesButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            imagesButton.widthAnchor.constraint(equalToConstant: 28),
            imagesButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 36)
    }

    func setImagesFilterActive(_ active: Bool) {
        imagesButton.state = active ? .on : .off
        imagesButton.contentTintColor = active ? NSColor.controlAccentColor : nil
    }

    @objc private func imagesButtonClicked(_ sender: NSButton) {
        onImagesFilterToggle?()
    }
}

/// Holds type-ahead keys from the moment a menu shortcut goes down until the
/// popup is tracking, then replays them into the menu one at a time.
///
/// The menu is built on the main thread after the shortcut, so a fast "2"
/// otherwise lands in the front app. This tap runs on its own thread and can
/// swallow those keys while the main thread is still building the menu.
private enum HotkeyTypeAheadCapture {
    private struct PendingKey {
        var keyCode: UInt16
        var characters: String
        var flags: CGEventFlags
    }

    private static let lock = NSLock()
    private static var armed = false
    private static var buffered: [PendingKey] = []
    private static var tap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?
    private static var thread: Thread?
    private static var tapRunLoop: CFRunLoop?
    private static var timeoutItem: DispatchWorkItem?
    private static var startTimer: Timer?
    private static var replayTimer: Timer?
    private static var acceptsReplay = false
    private static var replayWindowNumber = 0
    private static weak var pendingMenu: NSMenu?
    private static weak var pendingConfirmItem: NSMenuItem?
    private static var pendingReplayKeys: [PendingKey] = []
    private static let bufferLimit = 32
    private static let modifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static var isArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return armed
    }

    static func prepare() {
        // The tap thread must not start until its run-loop source exists.
        // CFRunLoopRunInMode returns immediately for an empty mode, and the
        // thread's loop would then peg a core for the life of the process.
        installTapIfNeeded()
    }

    static func arm() {
        // An open menu already owns the keyboard. Arming again would swallow
        // the digits the user is typing into that menu.
        guard !ClipMenuFilterKeyHook.isMenuSessionActive else { return }
        prepare()
        lock.lock()
        let alreadyArmed = armed
        armed = tap != nil
        lock.unlock()
        guard tap != nil else { return }
        if !alreadyArmed {
            enableTap(true)
        }
        scheduleTimeout()
    }

    /// Call just before `popUp`. The tap stays armed until menu tracking starts.
    static func scheduleReplay(windowNumber: Int, menu: NSMenu) {
        cancelTimeout()
        replayWindowNumber = windowNumber
        acceptsReplay = true
        pendingMenu = menu
        startTimer?.invalidate()
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let menu = HotkeyTypeAheadCapture.pendingMenu else { return }
                HotkeyTypeAheadCapture.replayIntoOpenMenu(menu)
            }
        }
        startTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    static func noteMenuClosed() {
        acceptsReplay = false
        pendingMenu = nil
        pendingConfirmItem = nil
        pendingReplayKeys = []
        startTimer?.invalidate()
        startTimer = nil
        replayTimer?.invalidate()
        replayTimer = nil
        releaseToSystemIfArmed()
    }

    static func releaseToSystemIfArmed() {
        let keys = disarmTakingBuffer()
        postToSystem(keys)
    }

    private static func replayIntoOpenMenu(_ menu: NSMenu) {
        let keys = disarmTakingBuffer()
        guard acceptsReplay else {
            postToSystem(keys)
            return
        }
        guard !keys.isEmpty else { return }
        HotkeyService.log.debug("Replaying \(keys.count, privacy: .public) type-ahead keys into the menu")

        let plan = replayPlan(for: keys)
        // Return must not be posted into NSMenu. A self-drawn row does not run
        // its action for that key, so the menu closes and nothing is pasted.
        // Choose the row from the keys typed before Return, then paste it on
        // the next tracking turn, once the menu is actually up.
        if plan.confirm, let item = matchingItem(prefix: plan.prefix, in: menu) {
            pendingConfirmItem = item
            pendingReplayKeys = plan.keysWithoutReturn
            let timer = Timer(timeInterval: 0, repeats: false) { _ in
                MainActor.assumeIsolated {
                    guard HotkeyTypeAheadCapture.acceptsReplay,
                          let item = HotkeyTypeAheadCapture.pendingConfirmItem else { return }
                    HotkeyTypeAheadCapture.pendingConfirmItem = nil
                    let fallback = HotkeyTypeAheadCapture.pendingReplayKeys
                    HotkeyTypeAheadCapture.pendingReplayKeys = []
                    if !CompactMenuRowView.activate(item) {
                        HotkeyTypeAheadCapture.pump(fallback)
                    }
                }
            }
            replayTimer = timer
            RunLoop.main.add(timer, forMode: .eventTracking)
            return
        }
        guard !plan.keysWithoutReturn.isEmpty else { return }
        pump(plan.keysWithoutReturn)
    }

    private struct ReplayPlan {
        var prefix: String
        var confirm: Bool
        var keysWithoutReturn: [PendingKey]
    }

    private static func replayPlan(for keys: [PendingKey]) -> ReplayPlan {
        var prefix = ""
        var confirm = false
        var replay: [PendingKey] = []
        for key in keys {
            if key.keyCode == 36 || key.keyCode == 76 {
                confirm = true
                break
            }
            replay.append(key)
            prefix += typeAheadText(for: key)
        }
        return ReplayPlan(prefix: prefix, confirm: confirm, keysWithoutReturn: replay)
    }

    /// A digit jumps to that numbered row (`2` → `2. …`), not to `20` or `2FA`.
    /// Any other prefix uses the same leading-title match as menu type-ahead.
    private static func matchingItem(prefix: String, in menu: NSMenu) -> NSMenuItem? {
        let needle = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let foldedNeedle = needle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let selectable: (NSMenuItem) -> Bool = { item in
            item.isEnabled && !item.isHidden && !item.isSeparatorItem && !(item.view is ClipMenuFilterBarView)
        }
        let foldedTitle: (NSMenuItem) -> String = { item in
            item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        if foldedNeedle.allSatisfy(\.isNumber) {
            if let numbered = menu.items.first(where: { item in
                guard selectable(item) else { return false }
                let title = foldedTitle(item)
                return title == foldedNeedle || title.hasPrefix(foldedNeedle + ".")
            }) {
                return numbered
            }
        }
        return menu.items.first { item in
            guard selectable(item) else { return false }
            return foldedTitle(item).hasPrefix(foldedNeedle)
        }
    }

    private static func typeAheadText(for key: PendingKey) -> String {
        if !key.characters.isEmpty,
           key.characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }) {
            return key.characters
        }
        switch key.keyCode {
        case 18, 83: return "1"
        case 19, 84: return "2"
        case 20, 85: return "3"
        case 21, 86: return "4"
        case 23, 87: return "5"
        case 22, 88: return "6"
        case 26, 89: return "7"
        case 28, 91: return "8"
        case 25, 92: return "9"
        case 29, 82: return "0"
        default: return ""
        }
    }

    private static func pump(_ keys: [PendingKey]) {
        guard acceptsReplay, let first = keys.first else { return }
        postToMenu(first)
        let rest = Array(keys.dropFirst())
        guard acceptsReplay, !rest.isEmpty else { return }
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                HotkeyTypeAheadCapture.pump(rest)
            }
        }
        replayTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private static func postToMenu(_ key: PendingKey) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags(from: key.flags),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: replayWindowNumber,
            context: nil,
            characters: key.characters,
            charactersIgnoringModifiers: key.characters,
            isARepeat: false,
            keyCode: key.keyCode
        ) else { return }
        NSApp.postEvent(event, atStart: true)
    }

    private static func disarmTakingBuffer() -> [PendingKey] {
        cancelTimeout()
        lock.lock()
        let wasArmed = armed
        armed = false
        let keys = buffered
        buffered.removeAll()
        lock.unlock()
        if wasArmed {
            enableTap(false)
        }
        return keys
    }

    private static func scheduleTimeout() {
        timeoutItem?.cancel()
        let item = DispatchWorkItem {
            HotkeyTypeAheadCapture.releaseToSystemIfArmed()
        }
        timeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }

    private static func cancelTimeout() {
        timeoutItem?.cancel()
        timeoutItem = nil
    }

    private static func capture(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let characters = characters(of: event)
        lock.lock()
        defer { lock.unlock() }
        guard armed else { return false }
        guard isTypeAheadKey(keyCode: keyCode, flags: flags) else { return false }
        if !isRepeat, buffered.count < bufferLimit {
            buffered.append(PendingKey(keyCode: UInt16(keyCode), characters: characters, flags: flags))
        }
        return true
    }

    private static func isTypeAheadKey(keyCode: Int64, flags: CGEventFlags) -> Bool {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return false
        }
        if modifierKeyCodes.contains(keyCode) { return false }
        if keyCode <= 93 { return true }
        switch keyCode {
        case 115, 116, 117, 119, 121, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    private static func characters(of event: CGEvent) -> String {
        let maxLength = 8
        var length = 0
        var buffer = [UniChar](repeating: 0, count: maxLength)
        event.keyboardGetUnicodeString(
            maxStringLength: maxLength,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: min(length, maxLength))
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    private static func postToSystem(_ keys: [PendingKey]) {
        guard !keys.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for key in keys {
            let down = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true)
            down?.flags = key.flags
            if !key.characters.isEmpty {
                var units = Array(key.characters.utf16)
                down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            }
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: false)
            up?.flags = key.flags
            up?.post(tap: .cghidEventTap)
        }
    }

    private static func enableTap(_ enabled: Bool) {
        lock.lock()
        let port = tap
        lock.unlock()
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: enabled)
    }

    private static func installTapIfNeeded() {
        lock.lock()
        let existing = tap
        let threadExists = thread != nil
        lock.unlock()
        guard AppDistribution.usesAccessibility else { return }
        guard existing == nil, !threadExists else { return }
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if HotkeyTypeAheadCapture.isArmed, let port = HotkeyTypeAheadCapture.machPort {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown, HotkeyTypeAheadCapture.capture(event) else {
                    return Unmanaged.passUnretained(event)
                }
                return nil
            },
            userInfo: nil
        ) else {
            HotkeyService.log.debug("Type-ahead capture tap unavailable")
            return
        }

        CGEvent.tapEnable(tap: created, enable: false)
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            HotkeyService.log.debug("Type-ahead capture run loop source unavailable")
            return
        }
        guard startThreadIfNeeded(source: source) else {
            HotkeyService.log.debug("Type-ahead capture thread did not attach its run loop")
            return
        }

        lock.lock()
        tap = created
        runLoopSource = source
        lock.unlock()
    }

    /// Starts the tap thread and returns once `source` is attached to its run loop.
    /// A second call does nothing: the thread is process-lifetime.
    private static func startThreadIfNeeded(source: CFRunLoopSource) -> Bool {
        lock.lock()
        if thread != nil {
            lock.unlock()
            return false
        }
        let started = DispatchSemaphore(value: 0)
        let newThread = Thread {
            let loop = CFRunLoopGetCurrent()
            // This thread only runs `.defaultMode`. The source has to be in
            // that mode before CFRunLoopRunInMode, or the mode is empty.
            CFRunLoopAddSource(loop, source, .defaultMode)
            HotkeyTypeAheadCapture.lock.lock()
            HotkeyTypeAheadCapture.tapRunLoop = loop
            HotkeyTypeAheadCapture.lock.unlock()
            started.signal()
            while !Thread.current.isCancelled {
                let result = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
                // `.finished` means this mode has no sources or timers. Calling
                // it again returns at once, so sleep instead of spinning.
                if result == .finished {
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
        newThread.name = "clipM.typeAhead"
        newThread.qualityOfService = .userInteractive
        thread = newThread
        lock.unlock()
        newThread.start()
        return started.wait(timeout: .now() + 2) == .success
    }

    private static var machPort: CFMachPort? {
        lock.lock()
        defer { lock.unlock() }
        return tap
    }
}

/// Intercepts `/` (and filter typing) before NSMenu type-ahead steals keys.
///
/// Primary path: CFRunLoop `beforeSources` observer in `.eventTracking` that
/// dequeues keyDowns from NSApp's queue (same Sonoma+ approach KeyboardShortcuts
/// uses — Carbon `GetEventDispatcherTarget` no longer sees menu keys).
/// Optional: CGEvent tap when Accessibility is granted (swallows earlier).
private enum ClipMenuFilterKeyHook {
    private static var eventTap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?
    private static var runLoopObserver: CFRunLoopObserver?
    private static var isDrainingEvents = false
    /// Mouse-up for the click that opened the menu. A session tap or a
    /// dequeued-and-reposted mouse-up makes a status-item menu close at once.
    private static var passOpeningMouseUp = false
    private static weak var activeTarget: HotkeyPopupActionTarget?
    private(set) static var eventTapInstalled = false
    private(set) static var runLoopMonitorInstalled = false
    static var isMenuSessionActive: Bool { activeTarget != nil }

    static func prepareAtLaunch() {
        installEventTapIfNeeded()
    }

    static func setActiveTarget(_ target: HotkeyPopupActionTarget?) {
        prepareAtLaunch()
        activeTarget = target
        // A status-item menu is opened by this click. The tap must stay off
        // until that mouse-up has reached AppKit, or the menu closes at once.
        passOpeningMouseUp = NSEvent.pressedMouseButtons != 0
        startRunLoopMonitorIfNeeded()
        if let eventTap, !passOpeningMouseUp {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    static func clearActiveTarget(_ target: HotkeyPopupActionTarget) {
        if activeTarget === target {
            activeTarget = nil
            passOpeningMouseUp = false
            stopRunLoopMonitor()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
        }
    }

    private static func finishOpeningClickIfIdle() {
        guard passOpeningMouseUp, NSEvent.pressedMouseButtons == 0 else { return }
        passOpeningMouseUp = false
        guard let eventTap else { return }
        DispatchQueue.main.async {
            guard activeTarget != nil, !passOpeningMouseUp else { return }
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private static func installEventTapIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1",
           ProcessInfo.processInfo.environment["CLIPMENU_ACTION_SMOKE_PHASE"]?.hasPrefix("no-tap-") == true { return }
        #endif
        guard AppDistribution.usesAccessibility else { return }
        guard eventTap == nil else { return }
        // Creating a session tap while untrusted raises the system Accessibility
        // dialog. That prompt belongs to the in-app paste explanation, not launch.
        guard AXIsProcessTrusted() else { return }

        let keyMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let mouseDownMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let mouseUpMask = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let mask = keyMask | mouseDownMask | mouseUpMask | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Stay disabled with no open menu, and during the click that
                    // opened a status-item menu. Re-enabling here undoes both.
                    if ClipMenuFilterKeyHook.activeTarget != nil,
                       !ClipMenuFilterKeyHook.passOpeningMouseUp,
                       let tap = ClipMenuFilterKeyHook.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                if ClipMenuFilterKeyHook.passOpeningMouseUp,
                   type == .leftMouseDown || type == .leftMouseUp
                    || type == .rightMouseDown || type == .rightMouseUp {
                    if type == .leftMouseUp { ClipMenuFilterKeyHook.passOpeningMouseUp = false }
                    return Unmanaged.passUnretained(event)
                }
                guard let target = ClipMenuFilterKeyHook.activeTarget else {
                    return Unmanaged.passUnretained(event)
                }

                var consume = false
                let handle = {
                    MainActor.assumeIsolated {
                        if type == .flagsChanged {
                            consume = target.handleGlobalActionModifierChange(cgEvent: event)
                        } else if type == .keyDown {
                            consume = target.handleGlobalKeyDown(cgEvent: event)
                            if !consume {
                                consume = target.handleGlobalActionKeyDown(cgEvent: event)
                            }
                        } else if type == .leftMouseDown {
                            consume = target.handleGlobalActionMouseDown(cgEvent: event)
                        } else if type == .rightMouseDown {
                            consume = target.handleGlobalActionMouseDown(cgEvent: event, rightClick: true)
                        } else if type == .leftMouseUp {
                            consume = target.handleGlobalActionMouseUp()
                        } else if type == .rightMouseUp {
                            consume = target.handleGlobalActionMouseUp(rightButton: true)
                        }
                    }
                }
                if Thread.isMainThread {
                    handle()
                } else {
                    DispatchQueue.main.sync(execute: handle)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            HotkeyService.log.debug("Filter event tap unavailable; using run-loop monitor")
            return
        }

        eventTap = tap
        eventTapInstalled = true
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        let tracking = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, tracking)
        // Taps are enabled when created. Leave this one off until a menu is open.
        // An enabled tap at launch puts the status-item click through the tap,
        // and that menu then closes. It can also swallow global hotkeys.
        CGEvent.tapEnable(tap: tap, enable: false)
        HotkeyService.log.debug("Filter key/mouse event tap installed")
    }

    private static func startRunLoopMonitorIfNeeded() {
        guard runLoopObserver == nil else { return }

        // Keys only. Dequeuing the opening mouse-up and posting it back closes
        // a status-item menu. Modifier-clicks are handled by the event tap.
        let keyMask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeSources.rawValue,
            true,
            0
        ) { _, _ in
            MainActor.assumeIsolated {
                guard ClipMenuFilterKeyHook.activeTarget != nil,
                      !ClipMenuFilterKeyHook.isDrainingEvents else { return }
                ClipMenuFilterKeyHook.isDrainingEvents = true
                defer { ClipMenuFilterKeyHook.isDrainingEvents = false }
                ClipMenuFilterKeyHook.finishOpeningClickIfIdle()

                // Intercept activation before NSMenu consumes it and closes the popup.
                // Dequeue only masked events: mouse-moved / pressure traffic often sits
                // ahead of a click and must stay queued for native highlight tracking.
                var pendingToRepost: [NSEvent] = []
                while let event = NSApp.nextEvent(
                    matching: keyMask,
                    // A nil deadline can wait for another event inside this observer,
                    // starving NSMenu's own tracking/drawing and accessibility work.
                    until: .distantPast,
                    inMode: .eventTracking,
                    dequeue: true
                ) {
                    let consumed: Bool
                    if let target = ClipMenuFilterKeyHook.activeTarget,
                       let cgEvent = event.cgEvent {
                        switch event.type {
                            case .flagsChanged:
                                consumed = target.handleGlobalActionModifierChange(cgEvent: cgEvent)
                            case .keyDown:
                                consumed = target.handleGlobalKeyDown(cgEvent: cgEvent)
                                    || target.handleGlobalActionKeyDown(cgEvent: cgEvent)
                            default:
                                consumed = false
                        }
                    } else {
                        consumed = false
                    }
                    if !consumed {
                        pendingToRepost.append(event)
                    }
                }

                for event in pendingToRepost.reversed() {
                    NSApp.postEvent(event, atStart: true)
                }
            }
        }

        runLoopObserver = observer
        let mode = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, mode)
        runLoopMonitorInstalled = true
        HotkeyService.log.debug("Filter key run-loop monitor installed")
    }

    private static func stopRunLoopMonitor() {
        guard let observer = runLoopObserver else { return }
        let mode = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, mode)
        runLoopObserver = nil
        runLoopMonitorInstalled = false
    }
}

@MainActor
private final class HotkeyPopupMenuPresenter: NSObject, NSMenuDelegate {
    private let actionTarget = HotkeyPopupActionTarget()
    private let previewController = ClipPreviewPanelController()
    private let isUITestMode = ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"
        && ProcessInfo.processInfo.environment["CLIPMENU_NATIVE_MENU_TEST"] != "1"
    private let testPopupStore = ClipMenuTestPopupStore.shared
    private var targetAppForPaste: NSRunningApplication?
    private var lastTargetApplication: NSRunningApplication?
    private var highlightPollingTimer: Timer?
    private weak var polledMenu: NSMenu?
    private var pendingPreviewItem: ClipPreviewItem?
    private var previewedItemID: PersistentIdentifier?
    private var currentSettings: ClipMenuSettings?
    private var previewAnchorPoint: NSPoint?
    private var activeMenuOrigin: NSPoint?
    private var rootMenuFrame: NSRect = .zero
    private var currentMenuFrame: NSRect = .zero
    private var previewSide: PreviewSide = .right
    private var knownMenuFrames: [NSRect] = []
    private var isStatusBarMenu = false
    private var statusBarMainMenuWidth: CGFloat = 0
    private var statusBarMenuRightEdge: CGFloat = 0
    private var previewRequestID = 0
    private weak var highlightedMenu: NSMenu?
    private weak var highlightedMenuItem: NSMenuItem?
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

    override init() {
        super.init()
        updateLastTargetApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @MainActor
    func show(using runtime: AppRuntime, kind: HotkeyMenuKind) {
        guard let context = runtime.modelContainer?.mainContext else {
            HotkeyService.log.error("Fallback popup requested but modelContext is nil")
            HotkeyTypeAheadCapture.releaseToSystemIfArmed()
            return
        }

        let menu = buildMenu(runtime: runtime, context: context, kind: kind)
        currentSettings = runtime.settings
        actionTarget.runtime = runtime
        targetAppForPaste = currentTargetApplication()
        actionTarget.targetAppForPaste = targetAppForPaste
        prepareMenuPreview(menu, settings: runtime.settings)

        if isUITestMode {
            testPopupStore.activationHandler = { [weak self] node in
                self?.activateTestNode(node)
            }
            testPopupStore.show(
                nodes: makeNodes(from: menu, level: 0, path: "root"),
                source: .hotkey
            )
            HotkeyService.log.notice("Presented UI-test popup window")
            HotkeyTypeAheadCapture.releaseToSystemIfArmed()
            return
        }

        let mouse = popupPresentationPoint()
        let anchorOrigin = popupAnchorOrigin(for: menu, mouse: mouse)
        anchorWindow.setFrameOrigin(anchorOrigin)
        activeMenuOrigin = anchorOrigin
        previewAnchorPoint = anchorOrigin
        let menuH = estimatedMenuHeight(for: menu)
        let menuW = estimatedMenuWidth(for: menu)
        currentMenuFrame = NSRect(x: anchorOrigin.x, y: anchorOrigin.y - menuH, width: menuW, height: menuH)
        rootMenuFrame = currentMenuFrame
        previewSide = preferredPreviewSide(for: currentMenuFrame)
        knownMenuFrames = [currentMenuFrame]
        anchorWindow.orderFront(nil)
        beginSlashKeyMonitorForOpenMenu()
        HotkeyTypeAheadCapture.scheduleReplay(windowNumber: anchorWindow.windowNumber, menu: menu)

        #if DEBUG
        let selfTestFilterSlash = ProcessInfo.processInfo.arguments.contains("--self-test-filter-slash")
        if selfTestFilterSlash {
            scheduleFilterSlashSelfTest(for: menu)
        }

        if ProcessInfo.processInfo.arguments.contains("--self-test-action-menu") {
            NativeActionMenuSmoke.start(menu: menu)
        }
        #endif
        runtime.closePreferences()
        NSApp.activate(ignoringOtherApps: true)
        if let contentView = anchorWindow.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: contentView)
        } else {
            menu.popUp(positioning: nil, at: mouse, in: nil)
        }

        stopHighlightPolling()
        anchorWindow.orderOut(nil)
        HotkeyTypeAheadCapture.noteMenuClosed()
        HotkeyService.log.notice("Presented fallback NSMenu popup")
    }

    #if DEBUG
    private func scheduleFilterSlashSelfTest(for menu: NSMenu) {
        fputs("[FILTER SELFTEST] scheduled\n", stderr)
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            fputs("[FILTER SELFTEST] timer fired\n", stderr)
            MainActor.assumeIsolated {
                self?.runFilterSlashSelfTest(menu: menu)
            }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func runFilterSlashSelfTest(menu: NSMenu) {
        fputs("[FILTER SELFTEST] running\n", stderr)
        ClipMenuFilterKeyHook.prepareAtLaunch()
        // Ensure the run-loop monitor is armed (menu-open path also does this).
        actionTarget.beginSlashKeyMonitorIfNeeded()

        guard actionTarget.filterSearchField != nil else {
            fputs("[FILTER SELFTEST] FAIL: filter search field missing\n", stderr)
            Darwin.exit(1)
        }

        if let screen = NSScreen.main {
            CGWarpMouseCursorPosition(CGPoint(x: screen.frame.minX + 2, y: screen.frame.minY + 2))
        }
        // Discover a working highlight API — setHighlightedItem: is absent on modern macOS.
        let highlightCandidates = ["highlightItem:", "setHighlightedItem:", "_highlightItem:"]
        var highlightSel: Selector?
        for name in highlightCandidates {
            let sel = NSSelectorFromString(name)
            if menu.responds(to: sel) {
                highlightSel = sel
                fputs("[FILTER SELFTEST] highlight API=\(name)\n", stderr)
                break
            }
        }
        if highlightSel == nil {
            var count: UInt32 = 0
            if let list = class_copyMethodList(NSMenu.self, &count) {
                defer { free(list) }
                var found: [String] = []
                for i in 0..<Int(count) {
                    let name = NSStringFromSelector(method_getName(list[i]))
                    if name.lowercased().contains("highlight") {
                        found.append(name)
                    }
                }
                fputs("[FILTER SELFTEST] NSMenu highlight methods=\(found)\n", stderr)
            }
        }

        let clearSel = highlightSel ?? NSSelectorFromString("highlightItem:")

        // Reproduce the user-visible bug: first content row is highlighted, then `/`.
        let firstContent = menu.items.first { item in
            let isCompactRow = item.view is CompactMenuRowView
            return (item.view == nil || isCompactRow)
                && item.isEnabled
                && !item.isSeparatorItem
                && !item.isHidden
                && item.title.hasPrefix("1.")
        }
        if let firstContent, menu.responds(to: clearSel) {
            menu.perform(clearSel, with: firstContent)
            fputs("[FILTER SELFTEST] pre-highlighted '\(firstContent.title.prefix(40))' now=\(menu.highlightedItem?.title.prefix(40) ?? "nil")\n", stderr)
        } else {
            fputs("[FILTER SELFTEST] WARN: could not pre-highlight (selResponds=\(menu.responds(to: clearSel)))\n", stderr)
        }

        if actionTarget.isFilterModeActiveForTesting {
            fputs("[FILTER SELFTEST] FAIL: filter mode already active before '/'\n", stderr)
            Darwin.exit(1)
        }

        // Post real key events into the app queue — do NOT call handleGlobalKeyDown
        // directly (that false-passed while AppKit still type-ahead-selected row 1).
        let winNum = NSApp.keyWindow?.windowNumber
            ?? actionTarget.filterSearchField?.window?.windowNumber
            ?? 0

        func postKey(_ keyCode: UInt16, chars: String) {
            guard let down = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: winNum,
                context: nil,
                characters: chars,
                charactersIgnoringModifiers: chars,
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            // atStart so the eventTracking run-loop monitor sees it before menu type-ahead.
            NSApp.postEvent(down, atStart: true)
        }

        postKey(44, chars: "/")

        let evaluate = Timer(timeInterval: 0.45, repeats: false) { _ in
            MainActor.assumeIsolated {
                let modeOn = self.actionTarget.isFilterModeActiveForTesting
                let highlighted = menu.highlightedItem
                let stillOnFirst = firstContent != nil && highlighted === firstContent
                let jumpedToContent = stillOnFirst
                    || highlighted?.representedObject is ClipEntry
                    || highlighted?.representedObject is Snippet
                    || (highlighted?.title.hasPrefix("1.") == true)

                guard modeOn, !jumpedToContent else {
                    fputs(
                        "[FILTER SELFTEST] FAIL after '/': mode=\(modeOn) highlighted=\(highlighted?.title ?? "nil") jumped=\(jumpedToContent) stillFirst=\(stillOnFirst) runloop=\(ClipMenuFilterKeyHook.runLoopMonitorInstalled) tap=\(ClipMenuFilterKeyHook.eventTapInstalled)\n",
                        stderr
                    )
                    menu.cancelTracking()
                    Darwin.exit(1)
                }

                // Simulate cursor still sitting on the first row (common real-world case).
                if let firstContent {
                    self.actionTarget.clipMenuWillHighlight(menu: menu, item: firstContent)
                    let modeAfterHover = self.actionTarget.isFilterModeActiveForTesting
                    let highlightedAfterHover = menu.highlightedItem
                    let hoverReselected = highlightedAfterHover === firstContent
                        || highlightedAfterHover?.title.hasPrefix("1.") == true
                    if !modeAfterHover || hoverReselected {
                        fputs(
                            "[FILTER SELFTEST] FAIL hover-after-/: mode=\(modeAfterHover) highlighted=\(highlightedAfterHover?.title ?? "nil") reselected=\(hoverReselected)\n",
                            stderr
                        )
                        menu.cancelTracking()
                        Darwin.exit(1)
                    }
                }

                postKey(0, chars: "a")

                let evaluate2 = Timer(timeInterval: 0.35, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        let query = self.actionTarget.filterSearchField?.stringValue ?? ""
                        let stillMode = self.actionTarget.isFilterModeActiveForTesting
                        let highlighted2 = menu.highlightedItem
                        let jumped2 = (firstContent != nil && highlighted2 === firstContent)
                            || highlighted2?.representedObject is ClipEntry
                            || highlighted2?.representedObject is Snippet
                            || (highlighted2?.title.hasPrefix("1.") == true)

                        if stillMode && query.lowercased().contains("a") && !jumped2 {
                            if firstContent?.isEnabled == false {
                                fputs("[FILTER SELFTEST] FAIL hovered row stayed disabled\n", stderr)
                                menu.cancelTracking()
                                Darwin.exit(1)
                            }
                            if let folder = menu.items.first(where: { $0.submenu != nil && !$0.isHidden }),
                               folder.isEnabled == false {
                                fputs("[FILTER SELFTEST] FAIL folder stayed disabled title=\(folder.title)\n", stderr)
                                menu.cancelTracking()
                                Darwin.exit(1)
                            }
                            self.actionTarget.toggleImagesOnlyFilter()
                            let imageRow = menu.items.first { item in
                                guard !item.isHidden, let clip = item.representedObject as? ClipEntry else { return false }
                                return clip.imageData != nil
                            }
                            if let imageRow {
                                self.actionTarget.clipMenuWillHighlight(menu: menu, item: imageRow)
                            }
                            if let folder = menu.items.first(where: { $0.submenu != nil && !$0.isHidden }) {
                                self.actionTarget.clipMenuWillHighlight(menu: menu, item: folder)
                                if !folder.isEnabled {
                                    fputs("[FILTER SELFTEST] FAIL image filter disabled folder title=\(folder.title)\n", stderr)
                                    menu.cancelTracking()
                                    Darwin.exit(1)
                                }
                            }
                            let settle = Timer(timeInterval: 0.05, repeats: false) { _ in
                                MainActor.assumeIsolated {
                                    if let imageRow, !imageRow.isEnabled {
                                        fputs("[FILTER SELFTEST] FAIL image row stayed disabled title=\(imageRow.title)\n", stderr)
                                        menu.cancelTracking()
                                        Darwin.exit(1)
                                    }
                                    fputs(
                                        "[FILTER SELFTEST] PASS: '/' filter mode; 'a' in query=\(query); no content jump; rows stayed enabled (runloop=\(ClipMenuFilterKeyHook.runLoopMonitorInstalled) tap=\(ClipMenuFilterKeyHook.eventTapInstalled))\n",
                                        stderr
                                    )
                                    menu.cancelTracking()
                                    Darwin.exit(0)
                                }
                            }
                            RunLoop.main.add(settle, forMode: .eventTracking)
                            RunLoop.main.add(settle, forMode: .common)
                            return
                        }
                        fputs(
                            "[FILTER SELFTEST] FAIL after 'a': mode=\(stillMode) query=\(query) highlighted=\(highlighted2?.title ?? "nil") jumped=\(jumped2)\n",
                            stderr
                        )
                        menu.cancelTracking()
                        Darwin.exit(1)
                    }
                }
                RunLoop.main.add(evaluate2, forMode: .eventTracking)
                RunLoop.main.add(evaluate2, forMode: .common)
            }
        }
        RunLoop.main.add(evaluate, forMode: .eventTracking)
        RunLoop.main.add(evaluate, forMode: .common)
    }

    #endif

    private func popupPresentationPoint() -> NSPoint {
        guard ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1",
              let window = NSApp.keyWindow ?? NSApp.mainWindow
        else {
            return NSEvent.mouseLocation
        }

        return NSPoint(x: window.frame.midX, y: window.frame.midY)
    }

    @MainActor
    func showStatusMenuForTesting(using runtime: AppRuntime) {
        guard let menu = statusMenu(using: runtime) else { return }
        prepareMenuPreview(menu, settings: runtime.settings)

        if isUITestMode {
            testPopupStore.activationHandler = { [weak self] node in
                self?.activateTestNode(node)
            }
            testPopupStore.show(
                nodes: makeNodes(from: menu, level: 0, path: "root"),
                source: .status
            )
            return
        }

        let point = NSPoint(x: NSScreen.main?.visibleFrame.midX ?? 400, y: NSScreen.main?.visibleFrame.midY ?? 400)
        activeMenuOrigin = point
        previewAnchorPoint = point
        startHighlightPolling(for: menu)
        menu.popUp(positioning: nil, at: point, in: nil)
        stopHighlightPolling()
        activeMenuOrigin = nil
        previewAnchorPoint = nil
    }

    private func popupAnchorOrigin(for menu: NSMenu, mouse: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let menuHeight = estimatedMenuHeight(for: menu)
        let bottomEdge = mouse.y - menuHeight
        
        let padding: CGFloat = 8
        if bottomEdge < frame.minY + padding {
            let requiredY = frame.minY + padding + menuHeight
            let finalY = min(requiredY, frame.maxY - padding)
            return NSPoint(x: mouse.x, y: finalY)
        }

        return mouse
    }

    private func estimatedMenuHeight(for menu: NSMenu) -> CGFloat {
        let visibleItems = menu.items.filter { !$0.isHidden }
        guard !visibleItems.isEmpty else { return 0 }
        return visibleItems.reduce(CGFloat(0)) { total, item in
            total + menuItemHeight(item)
        }
    }

    @MainActor
    func statusMenu(using runtime: AppRuntime, buttonMaxX: CGFloat? = nil) -> NSMenu? {
        guard let context = runtime.modelContainer?.mainContext else {
            HotkeyService.log.error("Status menu requested but modelContext is nil")
            return nil
        }

        let menu = buildMenu(runtime: runtime, context: context, kind: .main)
        currentSettings = runtime.settings
        actionTarget.runtime = runtime
        targetAppForPaste = currentTargetApplication()
        actionTarget.targetAppForPaste = targetAppForPaste
        isStatusBarMenu = true
        statusBarMainMenuWidth = estimatedMenuWidth(for: menu)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        let fallbackMaxX = screen?.visibleFrame.maxX ?? 1440
        statusBarMenuRightEdge = buttonMaxX ?? fallbackMaxX
        let menuH = estimatedMenuHeight(for: menu)
        let screenMaxY = screen?.visibleFrame.maxY ?? 900
        currentMenuFrame = NSRect(x: statusBarMenuRightEdge - statusBarMainMenuWidth, y: screenMaxY - menuH, width: statusBarMainMenuWidth, height: menuH)
        rootMenuFrame = currentMenuFrame
        previewSide = .left
        knownMenuFrames = [currentMenuFrame]
        prepareMenuPreview(menu, settings: runtime.settings)
        return menu
    }

    // Native LTR behavior preserves text alignment without structural hacks.

    @MainActor
    func prepareStatusMenuPreview(_ menu: NSMenu) {
        // The status controller owns root open/close and rebuild callbacks.
        // Preview preparation only owns the delegates of its child menus.
        let statusDelegate = menu.delegate
        prepareMenuPreview(menu, settings: currentSettings)
        menu.delegate = statusDelegate
        // Items were moved onto the live status menu — keep filter targeting that menu.
        if actionTarget.filterSearchField != nil {
            actionTarget.filterRootMenu = menu
        }
    }

    @MainActor
    func showPreviewForTesting(in menu: NSMenu) {
        guard let item = findFirstClipItem(in: menu),
              let clip = item.representedObject as? ClipEntry else { return }

        previewAnchorPoint = previewAnchorPoint(for: item, in: menu)
        pendingPreviewItem = nil
        previewRequestID += 1
        showPreview(for: .clip(clip))
    }

    private func findFirstClipItem(in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject is ClipEntry {
                return item
            }
            if let submenu = item.submenu, let child = findFirstClipItem(in: submenu) {
                return child
            }
        }
        return nil
    }

    @MainActor
    func showPreviewForTesting(_ clip: ClipEntry, at point: NSPoint) {
        previewAnchorPoint = point
        pendingPreviewItem = nil
        previewRequestID += 1
        showPreview(for: .clip(clip))
    }

    func menuDidClose(_ menu: NSMenu) {
        // Submenus close during normal navigation (e.g. moving between folders).
        // Only tear down the session when the root menu closes.
        guard menu.supermenu == nil else {
            previewController.hide()
            return
        }

        HotkeyTypeAheadCapture.noteMenuClosed()
        stopHighlightPolling()
        previewRequestID += 1
        previewedItemID = nil
        activeMenuOrigin = nil
        previewAnchorPoint = nil
        rootMenuFrame = .zero
        currentMenuFrame = .zero
        knownMenuFrames = []
        previewSide = .right
        isStatusBarMenu = false
        statusBarMainMenuWidth = 0
        statusBarMenuRightEdge = 0
        previewController.hide()
        highlightedMenu = nil
        highlightedMenuItem = nil
        clipMenuDidCloseCleanup()
        anchorWindow.orderOut(nil)
        testPopupStore.dismiss()
    }

    fileprivate func clipMenuDidCloseCleanup() {
        actionTarget.clipMenuFilterMenuDidClose()
    }

    fileprivate func beginSlashKeyMonitorForOpenMenu() {
        actionTarget.beginSlashKeyMonitorIfNeeded()
    }

    func menuWillOpen(_ menu: NSMenu) {
        beginSlashKeyMonitorForOpenMenu()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        menu.highlightedItem?.view?.needsDisplay = true
        item?.view?.needsDisplay = true
        actionTarget.clipMenuWillHighlight(menu: menu, item: item)
        handleHighlightedItem(item, in: menu)
        // AppKit owns hover, keyboard selection, and menu scrolling. Posting
        // synthetic scroll events here relocates the pointer to their location.
    }

    @MainActor
    private func prepareMenuPreview(_ menu: NSMenu, settings: ClipMenuSettings?) {
        currentSettings = settings
        menu.delegate = self

        for item in menu.items {
            item.toolTip = nil
            if let submenu = item.submenu {
                prepareMenuPreview(submenu, settings: settings)
            }
        }
    }

    @MainActor
    private func showPreview(for previewItem: ClipPreviewItem) {
        guard !ActionOverlayPresenter.shared.isVisible else { return }
        previewedItemID = previewItem.persistentModelID
        if !isUITestMode, let menu = highlightedMenu {
            updateMenuGeometry(for: menu)
            if let item = highlightedMenuItem {
                updatePreviewAnchor(for: item, in: menu)
            }
        }
        let anchor = previewAnchorPoint ?? NSEvent.mouseLocation
        previewController.show(
            item: previewItem,
            near: anchor,
            menuFrame: currentMenuFrame,
            preferredSide: previewSide,
            otherMenuFrames: knownMenuFrames,
            parentWindow: nil
        )
    }

    func dismissPreview(force: Bool = false) {
        if !force && previewController.panelWindow.isVisible {
            let mouse = NSEvent.mouseLocation
            let hoverRegion = previewController.panelWindow.frame.insetBy(dx: -20, dy: -10)
            if NSPointInRect(mouse, hoverRegion) {
                scheduleDismissalCheck()
                return
            }
        }

        dismissTimer?.invalidate()
        dismissTimer = nil
        previewDelayTimer?.invalidate()
        previewDelayTimer = nil
        pendingPreviewItem = nil
        previewRequestID += 1
        previewedItemID = nil
        previewController.hide()
    }

    private var dismissTimer: Timer?

    private func scheduleDismissalCheck() {
        dismissTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let mouse = NSEvent.mouseLocation
                if self.previewController.panelWindow.isVisible {
                    let hoverRegion = self.previewController.panelWindow.frame.insetBy(dx: -20, dy: -10)
                    if !NSPointInRect(mouse, hoverRegion) {
                        self.dismissPreview(force: true)
                    }
                } else {
                    self.dismissTimer?.invalidate()
                    self.dismissTimer = nil
                }
            }
        }
        dismissTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func highlightTestNode(_ node: TestPopupNode?, anchorPoint: NSPoint?) {
        guard currentSettings?.showTooltipsInMenu == true, let node else {
            dismissPreview()
            return
        }

        let previewItem: ClipPreviewItem
        if let clip = node.clip {
            previewItem = .clip(clip)
        } else if let snippet = node.snippet {
            previewItem = .snippet(snippet)
        } else {
            dismissPreview()
            return
        }

        if isUITestMode {
            NotificationCenter.default.post(
                name: .clipMenuHighlightDidChange,
                object: nil,
                userInfo: ["title": node.title]
            )
        }

        if let anchorPoint {
            previewAnchorPoint = anchorPoint
        }

        let itemID = previewItem.persistentModelID
        if previewedItemID == itemID || pendingPreviewItem?.persistentModelID == itemID {
            return
        }

        pendingPreviewItem = previewItem
        previewRequestID += 1
        let requestID = previewRequestID
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      self.previewRequestID == requestID,
                      self.pendingPreviewItem?.persistentModelID == itemID
                else { return }
                self.showPendingPreview()
            }
        }
    }

    func activateTestNode(_ node: TestPopupNode) {
        if let clip = node.clip {
            actionTarget.selectClipEntry(clip)
            return
        }

        if let snippet = node.snippet {
            actionTarget.selectSnippetModel(snippet)
        }
    }

    private func makeNodes(from menu: NSMenu, level: Int, path: String) -> [TestPopupNode] {
        menu.items.enumerated().map { index, item in
            let title = item.title.isEmpty && item.isSeparatorItem ? "separator-\(index)" : item.title
            let nodeID = "\(path).\(index)"
            let children = item.submenu.map { makeNodes(from: $0, level: level + 1, path: nodeID) } ?? []
            return TestPopupNode(
                id: nodeID,
                title: title,
                clip: item.representedObject as? ClipEntry,
                snippet: item.representedObject as? Snippet,
                children: children,
                // The filter field is a custom control, not a selectable row.
                // Compact title rows are still real menu entries.
                isEnabled: item.isEnabled && !(item.view is ClipMenuFilterBarView),
                isSeparator: item.isSeparatorItem,
                level: level
            )
        }
    }

    func testPopupDidDismiss() {
        dismissPreview()
    }

    private func showPendingPreview() {
        guard let item = pendingPreviewItem else { return }
        showPreview(for: item)
    }

    private func handleHighlightedItem(_ item: NSMenuItem?, in menu: NSMenu?) {
        guard currentSettings?.showTooltipsInMenu == true else {
            dismissPreview()
            return
        }

        let previewItem: ClipPreviewItem
        if let clip = item?.representedObject as? ClipEntry {
            previewItem = .clip(clip)
            if ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1" {
                NotificationCenter.default.post(
                    name: .clipMenuHighlightDidChange,
                    object: nil,
                    userInfo: ["title": clip.stringValue ?? ""]
                )
            }
        } else if let snippet = item?.representedObject as? Snippet {
            previewItem = .snippet(snippet)
        } else {
            dismissPreview()
            return
        }

        if let menu, let item {
            highlightedMenu = menu
            highlightedMenuItem = item
            if !isUITestMode {
                updateMenuGeometry(for: menu)
            }
            updatePreviewAnchor(for: item, in: menu)
        }

        let itemID = previewItem.persistentModelID
        if previewedItemID == itemID || pendingPreviewItem?.persistentModelID == itemID {
            return
        }

        schedulePreview(for: previewItem)
    }

    private var previewDelayTimer: Timer?

    private func schedulePreview(for previewItem: ClipPreviewItem) {
        previewDelayTimer?.invalidate()
        pendingPreviewItem = previewItem
        previewRequestID += 1
        let requestID = previewRequestID
        let itemID = previewItem.persistentModelID

        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.previewRequestID == requestID,
                      self.pendingPreviewItem?.persistentModelID == itemID
                else { return }
                self.showPendingPreview()
            }
        }
        previewDelayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func startHighlightPolling(for menu: NSMenu) {
        stopHighlightPolling()
        polledMenu = menu

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let menu = self.polledMenu else { return }
                if let (item, subMenu) = self.findHighlightedItemAndMenu(in: menu) {
                    self.handleHighlightedItem(item, in: subMenu)
                } else {
                    self.handleHighlightedItem(nil, in: menu)
                }
            }
        }
        highlightPollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func findHighlightedItemAndMenu(in menu: NSMenu) -> (NSMenuItem, NSMenu)? {
        if let item = menu.highlightedItem {
            if let submenu = item.submenu, let child = findHighlightedItemAndMenu(in: submenu) {
                return child
            }
            return (item, menu)
        }
        for item in menu.items {
            if let submenu = item.submenu, let child = findHighlightedItemAndMenu(in: submenu) {
                return child
            }
        }
        return nil
    }

    private func stopHighlightPolling() {
        highlightPollingTimer?.invalidate()
        highlightPollingTimer = nil
        polledMenu = nil
    }

    private func previewAnchorPoint(for item: NSMenuItem, in menu: NSMenu) -> NSPoint {
        if let rowCenter = highlightedRowCenter(for: item) {
            return rowCenter
        }
        return NSPoint(x: currentMenuFrame.midX, y: estimatedRowCenterY(for: item, in: menu))
    }

    private func updatePreviewAnchor(for item: NSMenuItem, in menu: NSMenu) {
        // Always line the preview up with the highlighted row. Mouse hover
        // already sits on that row; keyboard jumps leave the pointer behind.
        previewAnchorPoint = previewAnchorPoint(for: item, in: menu)
    }

    /// On-screen center of the highlighted row, when AppKit has laid it out.
    private func highlightedRowCenter(for item: NSMenuItem) -> NSPoint? {
        let frame = item.accessibilityFrame()
        guard frame.width > 1, frame.height > 1 else { return nil }
        if currentMenuFrame.width > 0 {
            let expanded = currentMenuFrame.insetBy(dx: -8, dy: -8)
            guard expanded.intersects(frame) else { return nil }
        }
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private func estimatedRowCenterY(for item: NSMenuItem, in menu: NSMenu) -> CGFloat {
        let visibleItems = menu.items.filter { !$0.isHidden }
        let itemIndex = max(visibleItems.firstIndex(of: item) ?? 0, 0)
        let rowOffset = visibleItems.prefix(itemIndex).reduce(CGFloat(0)) { total, current in
            total + menuItemHeight(current)
        } + menuItemHeight(item) / 2
        return currentMenuFrame.maxY - rowOffset
    }

    private func preferredPreviewSide(for menuFrame: NSRect) -> PreviewSide {
        if isStatusBarMenu { return .left }

        let probe = NSPoint(x: menuFrame.midX, y: menuFrame.midY)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(probe, $0.frame, false) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        guard visible.width > 0 else { return .right }

        let spaceOnLeft = menuFrame.minX - visible.minX
        let spaceOnRight = visible.maxX - menuFrame.maxX
        return spaceOnRight >= spaceOnLeft ? .right : .left
    }

    private func updateMenuGeometry(for menu: NSMenu) {
        let windows = visiblePopupMenuFrames()
        let isSubmenu = menu.supermenu != nil

        if !isSubmenu {
            if let actual = matchingMenuWindow(
                expected: rootMenuFrame.width > 0 ? rootMenuFrame : currentMenuFrame,
                in: windows,
                preferring: activeMenuOrigin
            ) {
                rootMenuFrame = actual
            } else if windows.count == 1 {
                rootMenuFrame = windows[0]
            }
            currentMenuFrame = rootMenuFrame
            knownMenuFrames = windows.isEmpty ? [rootMenuFrame] : windows
            previewSide = preferredPreviewSide(for: rootMenuFrame)
            return
        }

        if let actualRoot = matchingMenuWindow(expected: rootMenuFrame, in: windows, preferring: activeMenuOrigin) {
            rootMenuFrame = actualRoot
        }

        let expectedSide = preferredPreviewSide(for: rootMenuFrame)
        let estimatedSubmenu = estimatedSubmenuFrame(for: menu, root: rootMenuFrame, side: expectedSide)
        let submenuWindows = windows.filter { !isApproximatelySameWindow($0, rootMenuFrame) }

        if let submenu = matchingMenuWindow(expected: estimatedSubmenu, in: submenuWindows, preferring: nil)
            ?? submenuWindows.max(by: { abs($0.midX - rootMenuFrame.midX) < abs($1.midX - rootMenuFrame.midX) }) {
            currentMenuFrame = submenu
            previewSide = submenu.midX < rootMenuFrame.midX ? .left : .right
        } else {
            previewSide = expectedSide
            currentMenuFrame = estimatedSubmenu
        }

        knownMenuFrames = windows.isEmpty ? [rootMenuFrame, currentMenuFrame] : windows
    }

    private func estimatedSubmenuFrame(for menu: NSMenu, root: NSRect, side: PreviewSide) -> NSRect {
        let menuW = estimatedMenuWidth(for: menu)
        let menuH = estimatedMenuHeight(for: menu)
        let x = side == .right ? root.maxX : root.minX - menuW
        return NSRect(x: x, y: root.maxY - menuH, width: menuW, height: menuH)
    }

    private func isApproximatelySameWindow(_ a: NSRect, _ b: NSRect) -> Bool {
        if abs(a.midX - b.midX) < 30 && abs(a.minY - b.minY) < 40 {
            return true
        }
        let overlap = a.intersection(b)
        return overlap.width > min(a.width, b.width) * 0.6
    }

    private func matchingMenuWindow(expected: NSRect, in windows: [NSRect], preferring point: NSPoint?) -> NSRect? {
        if let point, let containing = windows.first(where: { NSPointInRect(point, $0) }) {
            if expected.width <= 0 || abs(containing.midX - expected.midX) < 80 {
                return containing
            }
        }

        guard expected.width > 0, !windows.isEmpty else { return windows.first }
        return windows.min { a, b in
            hypot(a.midX - expected.midX, a.midY - expected.midY) < hypot(b.midX - expected.midX, b.midY - expected.midY)
        }
    }

    private func visiblePopupMenuFrames() -> [NSRect] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let mainScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 900
        let previewFrame = previewController.panelWindow.isVisible ? previewController.panelWindow.frame : .null

        var frames: [NSRect] = []
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, (100...110).contains(layer),
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 40, rect.height > 20
            else { continue }

            let cocoaRect = NSRect(
                x: rect.origin.x,
                y: mainScreenHeight - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )

            if !previewFrame.isNull,
               cocoaRect.intersects(previewFrame.insetBy(dx: 4, dy: 4)),
               abs(cocoaRect.width - previewFrame.width) < 40 {
                continue
            }

            frames.append(cocoaRect)
        }
        return frames
    }

    /// Prefer attributed titles (image thumbnails) over plain `.title`; optionally
    /// include hidden rows so a filter toggle does not remasure against a narrower set.
    private func estimatedMenuWidth(for menu: NSMenu, includingHidden: Bool = false) -> CGFloat {
        let items = includingHidden ? menu.items : menu.items.filter { !$0.isHidden }
        let contentWidths: [CGFloat] = items.map { item in
            if let attributed = item.attributedTitle, attributed.length > 0 {
                return ceil(attributed.size().width)
            }
            return ceil((item.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width)
        }
        // +120 covers menu chrome (icons, padding, key equivalents); room for ~100pt thumbs.
        return min(max((contentWidths.max() ?? 220) + 120, 280), 520)
    }

    private func menuItemHeight(_ item: NSMenuItem) -> CGFloat {
        if item.isSeparatorItem { return 10 }
        if let height = item.view?.bounds.height, height > 1 { return height }
        if let attachment = CompactMenuRowView.attachmentHeight(of: item) {
            return max(22, attachment + 4)
        }
        return 22
    }

    private func currentTargetApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication, isValidTargetApplication(frontmost) {
            updateLastTargetApplication(frontmost)
            return frontmost
        }

        if let lastTargetApplication, !lastTargetApplication.isTerminated {
            return lastTargetApplication
        }

        return nil
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        updateLastTargetApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func updateLastTargetApplication(_ application: NSRunningApplication?) {
        guard let application, isValidTargetApplication(application) else { return }
        lastTargetApplication = application
    }

    private func isValidTargetApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != NSRunningApplication.current.processIdentifier
            && !application.isTerminated
            && application.activationPolicy == .regular
            && application.bundleIdentifier != nil
    }

    private func buildMenu(runtime: AppRuntime, context: ModelContext, kind: HotkeyMenuKind) -> NSMenu {
        let menu = NSMenu(title: AppDistribution.displayName)
        menu.minimumWidth = 240.0
        let settings = runtime.settings
        if kind != .actions {
            insertFilterMenuItems(into: menu)
        } else {
            actionTarget.filterRootMenu = nil
            actionTarget.filterSearchField = nil
            actionTarget.filterTitleMenuItem = nil
        }

        var clipsDescriptor: FetchDescriptor<ClipEntry>
        if kind == .actions || settings.reorderClipsAfterPasting {
            clipsDescriptor = FetchDescriptor(sortBy: [SortDescriptor(\ClipEntry.lastUsedAt, order: .reverse)])
        } else {
            clipsDescriptor = FetchDescriptor(sortBy: [SortDescriptor(\ClipEntry.createdAt, order: .reverse)])
        }
        clipsDescriptor.fetchLimit = kind == .actions ? 1 : max(settings.maxHistorySize, 1)
        let clips = kind == .snippets ? [] : ((try? context.fetch(clipsDescriptor)) ?? [])

        let folders = kind == .history || kind == .actions ? [] : ((try? context.fetch(FetchDescriptor<SnippetFolder>(
            sortBy: [SortDescriptor(\SnippetFolder.sortIndex, order: .forward)]
        ))) ?? [])

        let showSnippetsInMain = kind == .main
        let showHistory = kind != .snippets && kind != .actions

        let showSnippetsSection = (showSnippetsInMain && settings.positionOfSnippets != 2) || kind == .snippets

        if showSnippetsInMain && settings.positionOfSnippets == 0 {
            addSnippets(to: menu, folders: folders, settings: settings)
            addEditSnippetsItem(to: menu)
            if showHistory { menu.addItem(.separator()) }
        }

        if kind == .snippets {
            addSnippets(to: menu, folders: folders, settings: settings)
            addEditSnippetsItem(to: menu)
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
            addEditSnippetsItem(to: menu)
        }

        if showHistory && settings.showClearHistoryItem {
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History", action: #selector(HotkeyPopupActionTarget.clearHistory(_:)), keyEquivalent: "")
            clear.target = actionTarget
            clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            menu.addItem(clear)
        }

        menu.addItem(.separator())
        if !showSnippetsSection {
            addEditSnippetsItem(to: menu)
        }

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(HotkeyPopupActionTarget.openPreferences(_:)), keyEquivalent: "")
        prefs.target = actionTarget
        prefs.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(prefs)

        let quit = NSMenuItem(title: "Quit \(AppDistribution.displayName)", action: #selector(HotkeyPopupActionTarget.quit(_:)), keyEquivalent: "")
        quit.target = actionTarget
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        applyCompactMenuRows(in: menu)

        if kind != .actions {
            actionTarget.filterRootMenu = menu
            // Lock width after all items (incl. image thumbnails) exist so toggling
            // images-only filter does not remasure the popup from a different set of rows.
            let locked = estimatedMenuWidth(for: menu, includingHidden: true)
            menu.minimumWidth = locked
            actionTarget.lockedFilterMenuWidth = locked
            if let bar = actionTarget.filterImagesButtonHost {
                bar.frame.size.width = locked
            }
        } else {
            actionTarget.lockedFilterMenuWidth = nil
        }

        return menu
    }

    private func applyCompactMenuRows(in menu: NSMenu) {
        for item in menu.items {
            CompactMenuRowView.install(on: item)
            if let submenu = item.submenu {
                applyCompactMenuRows(in: submenu)
            }
        }
    }

    private func insertFilterMenuItems(into menu: NSMenu) {
        // Placeholder width; finalized once history/snippet rows are attached.
        let width = max(estimatedMenuWidth(for: menu, includingHidden: true), 280)
        let bar = ClipMenuFilterBarView(width: width)
        bar.searchField.delegate = actionTarget
        bar.onImagesFilterToggle = { [weak actionTarget] in
            actionTarget?.toggleImagesOnlyFilter()
        }
        bar.setImagesFilterActive(actionTarget.isImagesOnlyFilter)

        // Single search row. Do NOT set keyEquivalent to "/": AppKit then tries to
        // highlight this view-backed item, fails, and jumps to the first regular row.
        let filterItem = NSMenuItem(title: "Push / to search", action: nil, keyEquivalent: "")
        filterItem.toolTip = "Push / to search, then type to filter. Tab shows images only."
        filterItem.view = bar

        actionTarget.filterTitleMenuItem = filterItem
        actionTarget.filterSearchField = bar.searchField
        actionTarget.filterImagesButtonHost = bar

        menu.addItem(filterItem)
        menu.addItem(.separator())
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
        menu.addItem(actionClipIdentityItem(targetClip, settings: runtime.settings))
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
    private func addEditSnippetsItem(to menu: NSMenu) {
        let editSnippets = NSMenuItem(title: "Edit Snippets…", action: #selector(HotkeyPopupActionTarget.openSnippetsEditor(_:)), keyEquivalent: "")
        editSnippets.target = actionTarget
        editSnippets.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
        menu.addItem(editSnippets)
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
            folderItem.image = folderMenuIcon(settings: settings)
            let submenu = NSMenu(title: folder.title)
            submenu.minimumWidth = 240.0
            for snippet in snippets {
                let item = NSMenuItem(title: snippet.title, action: #selector(HotkeyPopupActionTarget.selectSnippetMenuItem(_:)), keyEquivalent: "")
                item.target = actionTarget
                item.representedObject = snippet
                item.clipMenuFilterHaystack = snippetFilterHaystack(snippet: snippet, folderTitle: folder.title)
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
                                  action: #selector(HotkeyPopupActionTarget.selectClipMenuItem(_:)),
                                  keyEquivalent: "")
            item.target = actionTarget
            item.representedObject = clip
            if let thumbnail = thumbnailImage(for: clip, settings: settings) {
                item.attributedTitle = imageClipTitle(title: item.title, thumbnail: thumbnail)
                HotkeyService.log.debug("Attached inline popup thumbnail for clip index=\(idx, privacy: .public)")
            } else if clip.imageData != nil {
                HotkeyService.log.debug("Inline popup clip has imageData but no thumbnail index=\(idx, privacy: .public) bytes=\(clip.imageData?.count ?? 0, privacy: .public)")
            }
            item.clipMenuFilterHaystack = clipFilterHaystack(clip)
            menu.addItem(item)
        }

        let groups = stride(from: 0, to: folderClips.count, by: perFolder).map {
            Array(folderClips[$0..<min($0 + perFolder, folderClips.count)])
        }

        for (groupIndex, group) in groups.enumerated() {
            let start = inlineCount + groupIndex * perFolder + 1
            let end = start + group.count - 1
            let folderItem = NSMenuItem(title: "\(start) - \(end)", action: nil, keyEquivalent: "")
            folderItem.image = folderMenuIcon(settings: settings)

            let submenu = NSMenu(title: folderItem.title)
            submenu.minimumWidth = 240.0
            for (idx, clip) in group.enumerated() {
                let absoluteIndex = inlineCount + groupIndex * perFolder + idx
                let itemNumber = listNumber(for: absoluteIndex, settings: settings)
                let item = NSMenuItem(title: clipTitle(for: clip, settings: settings, listNumber: itemNumber),
                                      action: #selector(HotkeyPopupActionTarget.selectClipMenuItem(_:)),
                                      keyEquivalent: "")
                item.target = actionTarget
                item.representedObject = clip
                if let thumbnail = thumbnailImage(for: clip, settings: settings) {
                    item.attributedTitle = imageClipTitle(title: item.title, thumbnail: thumbnail)
                    HotkeyService.log.debug("Attached grouped popup thumbnail group=\(groupIndex, privacy: .public) idx=\(idx, privacy: .public)")
                } else if clip.imageData != nil {
                    HotkeyService.log.debug("Grouped popup clip has imageData but no thumbnail group=\(groupIndex, privacy: .public) idx=\(idx, privacy: .public) bytes=\(clip.imageData?.count ?? 0, privacy: .public)")
                }
                item.clipMenuFilterHaystack = clipFilterHaystack(clip)
                submenu.addItem(item)
            }

            folderItem.submenu = submenu
            menu.addItem(folderItem)
        }
    }

    /// Visible 1-based (or 0-based) list index for menu titles.
    private func listNumber(for index: Int, settings: ClipMenuSettings) -> Int {
        if settings.numberingStartsAtZero {
            return index
        }
        return index + 1
    }

    /// The actions shortcut opens this menu without the clipboard popup, so the
    /// row has to say which clip the actions apply to.
    ///
    /// A disabled menu title is drawn in the dim header color. A custom view
    /// keeps the clip in the normal label color so it stays readable.
    private func actionClipIdentityItem(_ clip: ClipEntry, settings: ClipMenuSettings) -> NSMenuItem {
        let title = clipTitle(for: clip, settings: settings, listNumber: 1, includeNumber: false)
        var thumbnail: NSImage?
        if let imageData = clip.imageData, let image = decodedImage(from: imageData) {
            let targetSize = NSSize(width: CGFloat(max(settings.thumbnailWidth, 1)),
                                    height: CGFloat(max(settings.thumbnailHeight, 1)))
            thumbnail = scaledImage(image, to: targetSize)
        }
        let item = NSMenuItem(title: title.isEmpty ? "Image" : title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.view = ActionClipIdentityView(title: title, thumbnail: thumbnail)
        return item
    }

    private func clipTitle(for clip: ClipEntry, settings: ClipMenuSettings, listNumber: Int, includeNumber: Bool = true) -> String {
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

        let maxLen = max(settings.maxMenuItemTitleLength, 45) // Boost default bounds against old cached defaults of 20
        let trimmed: String
        if firstLine.count > maxLen {
            trimmed = String(firstLine.prefix(max(maxLen - 3, 0))) + "..."
        } else if firstLine.isEmpty, clip.imageData != nil {
            trimmed = ""
        } else {
            trimmed = firstLine.isEmpty ? "(binary)" : firstLine
        }

        if includeNumber && settings.numberedMenuItems {
            return trimmed.isEmpty ? "\(listNumber)." : "\(listNumber). \(trimmed)"
        }
        return trimmed
    }

    private func imageClipTitle(title: String, thumbnail: NSImage) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title.isEmpty ? "" : "\(title) ")
        let attachment = NSTextAttachment()
        attachment.image = thumbnail
        result.append(NSAttributedString(attachment: attachment))
        return result
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

    private func folderMenuIcon(settings: ClipMenuSettings) -> NSImage? {
        guard let image = NSImage(named: NSImage.folderName) else { return nil }
        let size = CGFloat(max(settings.menuIconSize, 1))
        return scaledImage(image, to: NSSize(width: size, height: size))
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

enum TestPopupSource {
    case hotkey
    case status
}

struct TestPopupNode: Identifiable {
    let id: String
    let title: String
    let clip: ClipEntry?
    let snippet: Snippet?
    let children: [TestPopupNode]
    let isEnabled: Bool
    let isSeparator: Bool
    let level: Int

    var isFolder: Bool { !children.isEmpty }
}

@MainActor
final class ClipMenuTestPopupStore: ObservableObject {
    static let shared = ClipMenuTestPopupStore()

    @Published private(set) var levels: [Int: [TestPopupNode]] = [:]
    @Published private(set) var selectedNodeIDs: [Int: String] = [:]
    @Published private(set) var previewNode: TestPopupNode?
    @Published private(set) var previewLevel: Int?
    @Published private(set) var source: TestPopupSource = .hotkey
    @Published private(set) var isVisible = false

    var activationHandler: ((TestPopupNode) -> Void)?
    private var previewTask: Task<Void, Never>?

    func show(nodes: [TestPopupNode], source: TestPopupSource) {
        dismiss()
        self.source = source
        levels[0] = nodes
        isVisible = true
        if let first = nodes.first(where: { !$0.isSeparator && $0.isEnabled }) {
            select(node: first, level: 0, openSubmenu: false, schedulePreview: source == .status)
        }
    }

    func dismiss() {
        previewTask?.cancel()
        previewTask = nil
        levels = [:]
        selectedNodeIDs = [:]
        previewNode = nil
        previewLevel = nil
        isVisible = false
    }

    func hover(node: TestPopupNode, level: Int) {
        select(node: node, level: level, openSubmenu: true, schedulePreview: true)
    }

    func moveSelection(delta: Int, level: Int) {
        guard let nodes = levels[level] else { return }
        let interactive = nodes.filter { !$0.isSeparator && $0.isEnabled }
        guard !interactive.isEmpty else { return }

        let currentIndex = interactive.firstIndex(where: { $0.id == selectedNodeIDs[level] }) ?? -1
        let nextIndex = max(0, min(interactive.count - 1, currentIndex + delta))
        select(node: interactive[nextIndex], level: level, openSubmenu: true, schedulePreview: true)
    }

    func openSelectedSubmenu(level: Int) {
        guard let selectedID = selectedNodeIDs[level],
              let node = levels[level]?.first(where: { $0.id == selectedID }),
              node.isFolder else { return }
        select(node: node, level: level, openSubmenu: true, schedulePreview: false)
    }

    func closeSubmenu(level: Int) {
        guard level > 0 else { return }
        for key in levels.keys where key >= level {
            levels.removeValue(forKey: key)
            selectedNodeIDs.removeValue(forKey: key)
        }
        previewNode = nil
        previewLevel = nil
    }

    func activateSelected(level: Int) {
        guard let selectedID = selectedNodeIDs[level],
              let node = levels[level]?.first(where: { $0.id == selectedID })
        else { return }

        if node.isFolder {
            select(node: node, level: level, openSubmenu: true, schedulePreview: false)
            return
        }

        activationHandler?(node)
        dismiss()
    }

    func openFirstFolderSubmenu() {
        guard let firstFolder = levels[0]?.first(where: { $0.isFolder && $0.isEnabled }) else { return }
        select(node: firstFolder, level: 0, openSubmenu: true, schedulePreview: false)
    }

    private func select(node: TestPopupNode, level: Int, openSubmenu: Bool, schedulePreview: Bool) {
        selectedNodeIDs[level] = node.id

        if ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1" {
            let title = node.clip?.stringValue ?? node.snippet?.title ?? node.title
            NotificationCenter.default.post(
                name: .clipMenuHighlightDidChange,
                object: nil,
                userInfo: ["title": title]
            )
        }

        if node.isFolder && openSubmenu {
            levels[level + 1] = node.children
            if let first = node.children.first(where: { !$0.isSeparator && $0.isEnabled }) {
                selectedNodeIDs[level + 1] = first.id
                schedulePreviewIfNeeded(for: first, level: level + 1)
            }
            return // Keep the selected child's preview request alive.
        } else {
            for key in levels.keys where key > level {
                levels.removeValue(forKey: key)
                selectedNodeIDs.removeValue(forKey: key)
            }
        }

        guard schedulePreview else {
            previewTask?.cancel()
            previewNode = nil
            previewLevel = nil
            return
        }

        schedulePreviewIfNeeded(for: node, level: level)
    }

    private func schedulePreviewIfNeeded(for node: TestPopupNode, level: Int) {
        previewTask?.cancel()
        previewNode = nil
        previewLevel = nil
        guard node.clip != nil || node.snippet != nil else { return }

        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            previewNode = node
            previewLevel = level
        }
    }

    func selectedNodeID(for level: Int) -> String? {
        selectedNodeIDs[level]
    }

    func nodes(for level: Int) -> [TestPopupNode] {
        levels[level] ?? []
    }

    func isSelected(_ node: TestPopupNode, level: Int) -> Bool {
        selectedNodeIDs[level] == node.id
    }
}

private enum ClipPreviewItem {
    case clip(ClipEntry)
    case snippet(Snippet)

    var persistentModelID: PersistentIdentifier {
        switch self {
        case .clip(let c): return c.persistentModelID
        case .snippet(let s): return s.persistentModelID
        }
    }
}

@MainActor
private final class ClipPreviewPanelController {
    private let panel: NSWindow
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private weak var parentWindow: NSWindow?
    private let isUITestMode = ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"

    init() {
        if isUITestMode {
            panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver // Maximum possible window-level to guarantee z-index superiority
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentViewController = hostingController
        if isUITestMode {
            panel.title = "Clip Preview"
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = true
            panel.isMovable = false
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.setAccessibilityIdentifier("clipPreviewPanel")
        } else if let panel = panel as? NSPanel {
            panel.isFloatingPanel = true
        }
    }

    var panelWindow: NSWindow { panel }

    func show(
        item: ClipPreviewItem,
        near point: NSPoint,
        menuFrame: NSRect = .zero,
        preferredSide: PreviewSide = .right,
        otherMenuFrames: [NSRect] = [],
        parentWindow: NSWindow? = nil
    ) {
        let size = ClipPreviewContentView.preferredSize(for: item)
        hostingController.rootView = AnyView(
            ClipPreviewContentView(item: item, preferredSize: size)
                .accessibilityIdentifier("clipPreviewContent")
        )
        panel.setContentSize(size)
        position(near: point, menuFrame: menuFrame, preferredSide: preferredSide, otherMenuFrames: otherMenuFrames)

        if self.parentWindow !== parentWindow {
            self.parentWindow?.removeChildWindow(panel)
            self.parentWindow = parentWindow
        }

        if let parentWindow {
            if panel.parent == nil {
                parentWindow.addChildWindow(panel, ordered: .above)
            }
            panel.orderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        if isUITestMode {
            let (title, hasImage): (String, Bool)
            switch item {
            case .clip(let clip):
                title = clip.stringValue ?? ""
                hasImage = clip.imageData != nil
            case .snippet(let snippet):
                title = snippet.title
                hasImage = false
            }
            NotificationCenter.default.post(
                name: .clipMenuPreviewDidShow,
                object: nil,
                userInfo: [
                    "title": title,
                    "hasImage": hasImage,
                    "frame": NSStringFromRect(panel.frame)
                ]
            )
        }
    }

    func hide() {
        parentWindow?.removeChildWindow(panel)
        parentWindow = nil
        panel.orderOut(nil)
        hostingController.rootView = AnyView(EmptyView())

        if isUITestMode {
            NotificationCenter.default.post(name: .clipMenuPreviewDidHide, object: nil)
        }
    }

    private func position(
        near point: NSPoint,
        menuFrame: NSRect,
        preferredSide: PreviewSide,
        otherMenuFrames: [NSRect]
    ) {
        let size = panel.frame.size
        let probe = menuFrame.width > 0 ? NSPoint(x: menuFrame.midX, y: menuFrame.midY) : point
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.screens.first(where: { NSMouseInRect(probe, $0.frame, false) })
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let gap: CGFloat = 8

        var y = point.y - (size.height / 2)
        if y < visible.minY + gap {
            y = visible.minY + gap
        }
        if y + size.height > visible.maxY - gap {
            y = visible.maxY - size.height - gap
        }

        let obstacles: [NSRect]
        if !otherMenuFrames.isEmpty {
            obstacles = otherMenuFrames
        } else if menuFrame.width > 0, menuFrame.height > 0 {
            obstacles = [menuFrame]
        } else {
            obstacles = []
        }

        let clusterSeed = menuFrame.width > 0 ? menuFrame : NSRect(origin: point, size: .zero)
        let cluster = obstacles.reduce(clusterSeed) { $0.union($1) }
        let adjacentFrame = menuFrame.width > 0 ? menuFrame : cluster

        func rect(beside frame: NSRect, side: PreviewSide) -> NSRect {
            let x = side == .left ? frame.minX - size.width - gap : frame.maxX + gap
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        func isOnscreen(_ rect: NSRect) -> Bool {
            rect.minX >= visible.minX + gap - 0.5 && rect.maxX <= visible.maxX - gap + 0.5
        }

        func overlapsMenus(_ rect: NSRect) -> Bool {
            guard !obstacles.isEmpty else { return false }
            let padded = rect.insetBy(dx: -2, dy: -2)
            return obstacles.contains { $0.intersects(padded) }
        }

        var chosen = rect(beside: adjacentFrame, side: preferredSide)
        if !isOnscreen(chosen) || overlapsMenus(chosen) {
            let outer = rect(beside: cluster, side: preferredSide)
            if isOnscreen(outer) && !overlapsMenus(outer) {
                chosen = outer
            } else {
                let flipped = rect(beside: cluster, side: preferredSide.flipped)
                if isOnscreen(flipped) && !overlapsMenus(flipped) {
                    chosen = flipped
                } else if isOnscreen(outer) {
                    chosen = outer
                } else if isOnscreen(flipped) {
                    chosen = flipped
                }
            }
        }

        var origin = chosen.origin
        let clampedX = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        let clampedRect = NSRect(x: clampedX, y: origin.y, width: size.width, height: size.height)
        if !overlapsMenus(clampedRect) {
            origin.x = clampedX
        }

        panel.setFrameOrigin(origin)
    }
}

private struct ClipPreviewContentView: View {
    let item: ClipPreviewItem
    let preferredSize: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: imageHeight)
            }

            if let text = textPreview {
                Text(text)
                    .font(.system(size: NSFont.systemFontSize))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(width: preferredSize.width, height: preferredSize.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var imageHeight: CGFloat {
        max(80, preferredSize.height - 28 - (textPreview == nil ? 0 : 70))
    }

    private var textPreview: String? {
        switch item {
        case .clip(let clip):
            if let stringValue = clip.stringValue, !stringValue.isEmpty { return stringValue }
            if let filenames = clip.filenames, !filenames.isEmpty { return filenames.joined(separator: "\n") }
            if let urls = clip.urlStrings, !urls.isEmpty { return urls.joined(separator: "\n") }
            return previewImage == nil ? "(binary)" : nil
        case .snippet(let snippet):
            return snippet.content.isEmpty ? "(empty)" : snippet.content
        }
    }

    private var previewImage: NSImage? {
        switch item {
        case .clip(let clip):
            return Self.clipImage(from: clip.imageData)
        case .snippet:
            return nil
        }
    }

    static func preferredSize(for item: ClipPreviewItem) -> CGSize {
        switch item {
        case .clip(let clip):
            return preferredSizeForClip(clip)
        case .snippet(let snippet):
            let text = snippet.content.isEmpty ? "(empty)" : snippet.content
            return preferredSizeForText(text)
        }
    }

    private static func preferredSizeForClip(_ clip: ClipEntry) -> CGSize {
        let horizontalPadding: CGFloat = 28
        let verticalPadding: CGFloat = 28
        let maxWidth: CGFloat = 480
        let minWidth: CGFloat = 200
        let maxHeight: CGFloat = 600
        let minHeight: CGFloat = 90

        if let image = clipImage(from: clip.imageData) {
            let maxImageWidth: CGFloat = 380
            let maxImageHeight: CGFloat = 280
            let scale = min(maxImageWidth / max(image.size.width, 1),
                            maxImageHeight / max(image.size.height, 1),
                            1)
            let imageWidth = max(120, image.size.width * scale)
            let imageHeight = max(90, image.size.height * scale)

            if let text = clipTextPreview(for: clip) {
                let textRect = text.boundingRect(
                    with: NSSize(width: max(imageWidth, 320), height: 1000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
                )
                let width = min(max(max(imageWidth, ceil(textRect.width)) + horizontalPadding, minWidth), maxWidth)
                let height = min(max(imageHeight + min(ceil(textRect.height), 280) + verticalPadding + 12, minHeight), maxHeight)
                return CGSize(width: width, height: height)
            }

            return CGSize(
                width: min(max(imageWidth + horizontalPadding, minWidth), maxWidth),
                height: min(max(imageHeight + verticalPadding, minHeight), maxHeight)
            )
        }

        let text = clipTextPreview(for: clip) ?? "(binary)"
        return preferredSizeForText(text)
    }

    private static func preferredSizeForText(_ text: String) -> CGSize {
        let horizontalPadding: CGFloat = 28
        let verticalPadding: CGFloat = 28
        let maxWidth: CGFloat = 480
        let minWidth: CGFloat = 220
        let maxHeight: CGFloat = 720
        let minHeight: CGFloat = 90
        let textWidth: CGFloat = 400

        let rect = text.boundingRect(
            with: NSSize(width: textWidth, height: 3000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )
        return CGSize(
            width: min(max(ceil(rect.width) + horizontalPadding, minWidth), maxWidth),
            height: min(max(ceil(rect.height) + verticalPadding, minHeight), maxHeight)
        )
    }

    private static func clipTextPreview(for clip: ClipEntry) -> String? {
        if let stringValue = clip.stringValue, !stringValue.isEmpty { return stringValue }
        if let filenames = clip.filenames, !filenames.isEmpty { return filenames.joined(separator: "\n") }
        if let urls = clip.urlStrings, !urls.isEmpty { return urls.joined(separator: "\n") }
        return nil
    }

    private static func clipImage(from data: Data?) -> NSImage? {
        guard let data else { return nil }
        if let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 { return image }
        if let rep = NSBitmapImageRep(data: data) {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            return image
        }
        return NSImage(data: data)
    }
}

private final class HotkeyPopupActionTarget: NSObject {
    private static let menuDismissSettleDelay: UInt64 = 40_000_000
    private static let reactivationSettleDelay: UInt64 = 40_000_000
    private static let prePasteDelay: UInt64 = 70_000_000

    weak var runtime: AppRuntime?
    weak var targetAppForPaste: NSRunningApplication?
    weak var filterRootMenu: NSMenu?
    weak var filterSearchField: ClipMenuSearchField?
    weak var filterTitleMenuItem: NSMenuItem?
    weak var filterImagesButtonHost: ClipMenuFilterBarView?
    /// Width locked when the menu is built so filter toggles do not resize the popup.
    var lockedFilterMenuWidth: CGFloat?
    /// True after `/` until Escape / ↓ / highlight leaves the filter.
    private(set) var isFilterModeActive = false
    /// When true, only clipboard rows with image data remain visible.
    private(set) var isImagesOnlyFilter = false
    private var isSuppressingContentHighlight = false
    /// Rows briefly disabled so AppKit drops the tracking highlight. Restored
    /// on the menu-tracking run loop. A main-queue async does not run while
    /// the menu is open, which left the row drawn gray.
    private var highlightMutedItems: [NSMenuItem] = []
    private var highlightRestoreTimer: Timer?
    private let pasteService = PasteService()
    /// Modifiers observed while the popup menu is open (flags can clear before the item action runs).
    private var trackedModifierFlags: NSEvent.ModifierFlags = []
    private var lastClickModifierFlags: NSEvent.ModifierFlags = []
    private var lastClickLocation: NSPoint?
    private var modifierMonitor: Any?
    /// Last row from `menu:willHighlight:` — used for modifier+click action overlay.
    private weak var lastHighlightedMenuItem: NSMenuItem?
    /// Swallow the matching mouseUp after we intercept a modifier-click or right-click.
    private var suppressNextMouseUpForActionOverlay = false
    private var suppressNextRightMouseUpForActionOverlay = false
    /// Skip paste when the activating click was already handled as an action overlay.
    private var ignoreNextClipSelectionForActionOverlay = false

    func beginSlashKeyMonitorIfNeeded() {
        installModifierMonitorIfNeeded()
        // Intercept action-modifier clicks before NSMenu pastes the clip.
        // The filter field is unrelated to that intercept.
        ClipMenuFilterKeyHook.setActiveTarget(self)
    }

    private func installModifierMonitorIfNeeded() {
        guard modifierMonitor == nil else { return }
        trackedModifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        modifierMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .keyDown]
        ) { [weak self] event in
            let consume = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                // The overlay is already visible by the time the matching mouse-up
                // arrives. Swallow that release before the visibility check, or the
                // clip menu closes out from under the action panel.
                if event.type == .rightMouseUp, self.suppressNextRightMouseUpForActionOverlay {
                    self.suppressNextRightMouseUpForActionOverlay = false
                    return true
                }
                if event.type == .leftMouseUp, self.suppressNextMouseUpForActionOverlay {
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if !flags.isEmpty { self.lastClickModifierFlags = flags }
                    self.suppressNextMouseUpForActionOverlay = false
                    return true
                }
                if ActionOverlayPresenter.shared.isVisible { return false }
                if event.type == .flagsChanged, let cgEvent = event.cgEvent {
                    return self.handleGlobalActionModifierChange(cgEvent: cgEvent)
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.trackedModifierFlags = flags

                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    self.lastClickModifierFlags = flags
                    self.lastClickLocation = NSEvent.mouseLocation
                } else if event.type == .leftMouseUp {
                    if !flags.isEmpty { self.lastClickModifierFlags = flags }
                }

                if event.type == .rightMouseDown,
                   self.tryPresentActionOverlay(from: event, requireModifier: false) {
                    self.suppressNextRightMouseUpForActionOverlay = true
                    return true
                }

                if event.type == .leftMouseDown || event.type == .keyDown,
                   self.tryPresentActionOverlay(from: event) {
                    if event.type == .leftMouseDown {
                        self.suppressNextMouseUpForActionOverlay = true
                        self.ignoreNextClipSelectionForActionOverlay = true
                    }
                    return true
                }
                return false
            }
            return consume ? nil : event
        }
    }

    private func removeModifierMonitor() {
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
            self.modifierMonitor = nil
        }
        trackedModifierFlags = []
        lastHighlightedMenuItem = nil
        suppressNextMouseUpForActionOverlay = false
        suppressNextRightMouseUpForActionOverlay = false
        ignoreNextClipSelectionForActionOverlay = false
        // Defer clearing click modifiers so any menu item selection action dispatched
        // in the current run-loop cycle still sees them.
        DispatchQueue.main.async { [weak self] in
            self?.lastClickModifierFlags = []
            self?.lastClickLocation = nil
        }
    }

    private func selectionModifierFlags() -> NSEvent.ModifierFlags {
        let fromEvent = (NSApp.currentEvent?.modifierFlags ?? []).intersection(.deviceIndependentFlagsMask)
        let live = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return fromEvent.union(live).union(trackedModifierFlags).union(lastClickModifierFlags)
    }

    /// Called from the CGEvent tap on the main thread. Return true to swallow the key.
    @MainActor
    fileprivate func handleGlobalKeyDown(cgEvent: CGEvent) -> Bool {
        guard !ActionOverlayPresenter.shared.isVisible else { return false }
        guard filterSearchField != nil else { return false }

        let flags = cgEvent.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return false
        }

        let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        let shift = flags.contains(.maskShift)

        if !isFilterModeActive {
            // Return does not activate a self-drawn row. Perform it here.
            // Numbers and letters still go to menu type-ahead ("5" then Return).
            if keyCode == 36 || keyCode == 76, let item = deepestHighlightedCompactItem() {
                return CompactMenuRowView.activate(item)
            }
            // Only `/` enters filter mode. Leave numbers/letters for menu type-ahead.
            guard isUnmodifiedSlash(keyCode: keyCode, shift: shift, cgEvent: cgEvent) else {
                return false
            }
            enterFilterMode()
            return true
        }

        // Filter mode: own typing so the menu cannot type-ahead.
        switch keyCode {
        case 53: // escape
            exitFilterMode(clearQuery: true)
            return true
        case 125: // down arrow — hand control back to the menu list
            exitFilterMode(clearQuery: false)
            return false
        case 51: // delete
            deleteLastFilterCharacter()
            return true
        case 36, 76: // return / keypad enter — stay in filter, don't activate a row
            return true
        case 48: // tab — toggle images-only filter
            toggleImagesOnlyFilter()
            return true
        default:
            if let chars = characters(from: cgEvent), !chars.isEmpty {
                appendFilterCharacters(chars)
                return true
            }
            // Unknown key while filtering — swallow to avoid accidental menu jumps.
            return true
        }
    }

    var isFilterModeActiveForTesting: Bool { isFilterModeActive }

    private func enterFilterMode() {
        isFilterModeActive = true
        // IMPORTANT: never setHighlightedItem(filterRow). AppKit cannot highlight a
        // view-backed row and jumps to the first real menu item — the bug users saw.
        clearMenuHighlight()
        filterSearchField?.activateForTypingFromMenuHighlight()
        applyCurrentFilterQuery()
        HotkeyService.log.debug("Filter mode ON")
    }

    private func exitFilterMode(clearQuery: Bool) {
        restoreHighlightMutedItems()
        isFilterModeActive = false
        if clearQuery, let field = filterSearchField {
            field.stringValue = ""
            setImagesOnlyFilter(false)
            applyCurrentFilterQuery()
        }
        filterSearchField?.releaseTypingCaptureForMenuNavigation()
        if let window = filterSearchField?.window ?? NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }
        HotkeyService.log.debug("Filter mode OFF")
    }

    func toggleImagesOnlyFilter() {
        setImagesOnlyFilter(!isImagesOnlyFilter)
        if isImagesOnlyFilter, !isFilterModeActive {
            enterFilterMode()
        } else {
            applyCurrentFilterQuery()
        }
    }

    private func setImagesOnlyFilter(_ enabled: Bool) {
        isImagesOnlyFilter = enabled
        filterImagesButtonHost?.setImagesFilterActive(enabled)
    }

    /// Folders, and clips inside an open folder, have to stay highlighted or the submenu will not open.
    private func keepsHighlightWhileFiltering(_ item: NSMenuItem, in menu: NSMenu) -> Bool {
        item.submenu != nil || menu.supermenu != nil
    }

    /// Drops the blue menu highlight without a private `highlightItem:` call.
    /// Disabling the tracked row clears it. Enabling the row again does not
    /// bring the highlight back. A row AppKit is about to highlight has to stay
    /// disabled until `menu(_:willHighlight:)` returns, then it is restored.
    private func clearMenuHighlight(cancelling pending: NSMenuItem? = nil, restoreImmediately: Bool = true) {
        guard let menu = filterTitleMenuItem?.menu ?? filterRootMenu else { return }
        muteHighlight(on: menu.highlightedItem)
        muteHighlight(on: pending)
        guard !highlightMutedItems.isEmpty else { return }
        if restoreImmediately {
            restoreHighlightMutedItems()
        } else {
            scheduleHighlightRestore()
        }
    }

    private func muteHighlight(on item: NSMenuItem?) {
        guard let item, item.isEnabled, !item.isSeparatorItem else { return }
        let isCompactRow = item.view is CompactMenuRowView
        guard item.view == nil || isCompactRow else { return }
        // Disabling a folder cancels its submenu and draws the title gray.
        guard item.submenu == nil else { return }
        guard !highlightMutedItems.contains(where: { $0 === item }) else { return }
        item.isEnabled = false
        item.view?.needsDisplay = true
        highlightMutedItems.append(item)
    }

    private func scheduleHighlightRestore() {
        highlightRestoreTimer?.invalidate()
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            self?.restoreHighlightMutedItems()
        }
        highlightRestoreTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func restoreHighlightMutedItems() {
        highlightRestoreTimer?.invalidate()
        highlightRestoreTimer = nil
        for item in highlightMutedItems {
            item.isEnabled = true
            item.view?.needsDisplay = true
        }
        highlightMutedItems.removeAll()
    }

    private func appendFilterCharacters(_ chars: String) {
        guard let field = filterSearchField else { return }
        field.stringValue += chars
        syncFilterFieldEditor(field)
        applyCurrentFilterQuery()
    }

    private func deleteLastFilterCharacter() {
        guard let field = filterSearchField, !field.stringValue.isEmpty else { return }
        field.stringValue.removeLast()
        syncFilterFieldEditor(field)
        applyCurrentFilterQuery()
    }

    private func syncFilterFieldEditor(_ field: ClipMenuSearchField) {
        guard let window = field.window ?? NSApp.keyWindow,
              let editor = window.fieldEditor(false, for: field) as? NSTextView
        else {
            field.refreshFallbackCaret()
            return
        }
        if editor.string != field.stringValue {
            editor.string = field.stringValue
        }
        let end = editor.string.utf16.count
        editor.setSelectedRange(NSRange(location: end, length: 0))
        editor.insertionPointColor = .clear
        field.refreshFallbackCaret()
    }

    private func applyCurrentFilterQuery() {
        guard let field = filterSearchField else { return }
        let menu = field.enclosingMenuItem?.menu ?? filterRootMenu
        guard let menu else { return }
        ClipMenuFilter.apply(query: field.stringValue, imagesOnly: isImagesOnlyFilter, to: menu)
        // Re-assert after visibility changes — AppKit otherwise remasures from visible rows.
        if let locked = lockedFilterMenuWidth {
            menu.minimumWidth = locked
            filterImagesButtonHost?.frame.size.width = locked
        }
    }

    /// The row the user would confirm: the highlighted item inside an open submenu, otherwise the highlighted root row.
    private func deepestHighlightedCompactItem() -> NSMenuItem? {
        func walk(_ menu: NSMenu?) -> NSMenuItem? {
            guard let menu, let item = menu.highlightedItem else { return nil }
            if let deeper = walk(item.submenu) { return deeper }
            return item.view is CompactMenuRowView ? item : nil
        }
        return walk(filterRootMenu)
    }

    private func isUnmodifiedSlash(keyCode: Int64, shift: Bool, cgEvent: CGEvent) -> Bool {
        if keyCode == 75 { return true } // keypad /
        if keyCode == 44 { return !shift } // `/` vs `?`
        if let chars = characters(from: cgEvent), chars == "/" { return true }
        return false
    }

    private func characters(from cgEvent: CGEvent) -> String? {
        guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return nil }
        return nsEvent.characters
    }

    /// Mouse highlight: hovering the filter row can enter filter mode. While filtering,
    /// content-row hover must NOT exit filter mode (mouse often still sits on row 1 after `/`).
    @MainActor
    func clipMenuWillHighlight(menu: NSMenu, item: NSMenuItem?) {
        if !isFilterModeActive {
            lastHighlightedMenuItem = item
        }
        guard let field = filterSearchField, let filterItem = filterTitleMenuItem else { return }
        let isFilterRow = item === filterItem
            || (item?.view != nil && field.isDescendant(of: item!.view!))
        if isFilterRow {
            if !isFilterModeActive {
                enterFilterMode()
            }
            return
        }
        if isFilterModeActive {
            // Suppress content highlight while filtering — otherwise AppKit immediately
            // re-highlights the row under the cursor and `/` looks like it "selected" it.
            // Folders and the rows inside them must stay enabled, or the submenu
            // never opens and the folder title is drawn gray.
            if let item, !keepsHighlightWhileFiltering(item, in: menu), !isSuppressingContentHighlight {
                isSuppressingContentHighlight = true
                defer { isSuppressingContentHighlight = false }
                clearMenuHighlight(cancelling: item, restoreImmediately: false)
            }
            return
        }
    }

    func clipMenuFilterMenuDidClose() {
        restoreHighlightMutedItems()
        MainActor.assumeIsolated { ActionOverlayPresenter.shared.parentMenuDidClose() }
        isFilterModeActive = false
        setImagesOnlyFilter(false)
        removeModifierMonitor()
        ClipMenuFilterKeyHook.clearActiveTarget(self)
        filterRootMenu = nil
        filterSearchField?.releaseTypingCaptureForMenuNavigation()
        if let field = filterSearchField {
            field.stringValue = ""
        }
        filterImagesButtonHost = nil
        lockedFilterMenuWidth = nil
    }

    private func moveFilterFocusToMenuList(field: ClipMenuSearchField) {
        exitFilterMode(clearQuery: false)
        let winNum = field.window?.windowNumber ?? NSApp.keyWindow?.windowNumber ?? 0
        DispatchQueue.main.async { [weak self] in
            self?.repostMenuListArrowKeyDown(windowNumber: winNum)
        }
    }

    private func repostMenuListArrowKeyDown(windowNumber: Int) {
        guard let replay = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        ) else { return }
        NSApp.postEvent(replay, atStart: false)
    }

    @MainActor
    private func reactivateTargetAppIfNeeded() {
        if let targetAppForPaste {
            HotkeyService.log.debug("Re-activating target app pid=\(targetAppForPaste.processIdentifier, privacy: .public)")
            NSApp.hide(nil)
            targetAppForPaste.activate(options: [])
        } else {
            NSApp.hide(nil)
        }
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        guard let clip = sender.representedObject as? ClipEntry, let runtime else { return }

        if ignoreNextClipSelectionForActionOverlay {
            ignoreNextClipSelectionForActionOverlay = false
            return
        }

        let wantsActions = runtime.settings.enableAction && isActionModifierHeld()
        let clickPoint = lastClickLocation ?? NSEvent.mouseLocation
        lastClickModifierFlags = []
        lastClickLocation = nil

        if wantsActions {
            // Fallback if the event tap/local monitor missed the click (menu may already be closing).
            actionDebugLog("click reached row activation (intercept missed)")
            _ = MainActor.assumeIsolated {
                self.presentActionMenu(for: clip, at: clickPoint, runtime: runtime, from: sender)
            }
            return
        }
        selectClipEntry(clip)
    }

    private func actionModifierMask(for key: Int) -> NSEvent.ModifierFlags {
        switch key {
        case 1: return .command
        case 2: return .control
        case 3: return .shift
        default: return .option
        }
    }

    private func isActionModifierHeld() -> Bool {
        guard let runtime else { return false }
        return selectionModifierFlags().contains(actionModifierMask(for: runtime.settings.actionModifierKey))
    }

    /// Right-click, or hold the action modifier and click/Return, opens an action panel at the pointer.
    @MainActor
    @discardableResult
    private func tryPresentActionOverlay(from event: NSEvent, requireModifier: Bool = true) -> Bool {
        guard let runtime, runtime.settings.enableAction else { return false }

        if requireModifier {
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .union(trackedModifierFlags)
                .union(NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
            guard flags.contains(actionModifierMask(for: runtime.settings.actionModifierKey)) else {
                actionDebugLog("mouseDown uses normal paste: flags=\(flags.rawValue) configuredModifier=\(runtime.settings.actionModifierKey)")
                return false
            }
        }

        if event.type == .keyDown {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            guard isReturn else { return false }
        }

        let item = event.type == .leftMouseDown || event.type == .rightMouseDown
            ? actionMenuItem(at: NSEvent.mouseLocation, in: filterRootMenu)
            : (lastHighlightedMenuItem
                ?? filterRootMenu?.highlightedItem
                ?? findHighlightedMenuItem(in: filterRootMenu))
        guard let item, let clip = actionTargetClip(from: item) else { return false }

        let anchor = event.type == .keyDown ? actionMenuAnchor(over: item) : NSEvent.mouseLocation
        return presentActionMenu(for: clip, at: anchor, runtime: runtime, from: item)
    }

    /// Track the action modifier; do not open the overlay here. Opening on the
    /// modifier-down edge alone means the following click lands on the still-tracked
    /// menu row, activates it, and dismisses the main popup.
    @MainActor
    fileprivate func handleGlobalActionModifierChange(cgEvent: CGEvent) -> Bool {
        trackedModifierFlags = cgEventFlagsToModifierFlags(cgEvent.flags)
        return false
    }

    /// CGEvent-tap path: action-modifier + Return opens the overlay without activating the row.
    @MainActor
    fileprivate func handleGlobalActionKeyDown(cgEvent: CGEvent) -> Bool {
        guard !ActionOverlayPresenter.shared.isVisible else { return false }
        guard filterRootMenu != nil else { return false }
        let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 36 || keyCode == 76 else { return false }

        let flags = cgEventFlagsToModifierFlags(cgEvent.flags)
        trackedModifierFlags = flags
        guard let runtime, runtime.settings.enableAction else { return false }
        guard flags.contains(actionModifierMask(for: runtime.settings.actionModifierKey)) else {
            return false
        }

        let item = lastHighlightedMenuItem
            ?? filterRootMenu?.highlightedItem
            ?? findHighlightedMenuItem(in: filterRootMenu)
        guard let item, let clip = actionTargetClip(from: item) else { return false }

        return presentActionMenu(for: clip, at: actionMenuAnchor(over: item), runtime: runtime, from: item)
    }

    /// CGEvent-tap path: consume a right-click or modifier-click before the clip is pasted.
    @MainActor
    fileprivate func handleGlobalActionMouseDown(cgEvent: CGEvent, rightClick: Bool = false) -> Bool {
        guard !ActionOverlayPresenter.shared.isVisible else { return false }
        guard filterRootMenu != nil else {
            actionDebugLog("mouseDown ignored: no open clip menu")
            return false
        }
        let flags = cgEventFlagsToModifierFlags(cgEvent.flags)
        trackedModifierFlags = flags
        lastClickModifierFlags = flags
        lastClickLocation = NSEvent.mouseLocation

        guard let runtime, runtime.settings.enableAction else { return false }
        if !rightClick {
            guard flags.contains(actionModifierMask(for: runtime.settings.actionModifierKey)) else {
                return false
            }
        }

        let eventPoint = NSPoint(
            x: cgEvent.location.x,
            y: (NSScreen.screens.first?.frame.maxY ?? 0) - cgEvent.location.y
        )
        guard let item = actionMenuItem(at: eventPoint, in: filterRootMenu),
              let clip = actionTargetClip(from: item) else {
            actionDebugLog("mouseDown ignored: no highlighted clip row")
            return false
        }

        let presented = presentActionMenu(for: clip, at: NSEvent.mouseLocation, runtime: runtime, from: item)
        actionDebugLog("mouseDown swallowed=\(presented) rightClick=\(rightClick)")
        if presented {
            if rightClick {
                // A right-click does not activate the row, so leave the next
                // left-click free to paste. Only the matching right-up is swallowed.
                suppressNextRightMouseUpForActionOverlay = true
            } else {
                suppressNextMouseUpForActionOverlay = true
                ignoreNextClipSelectionForActionOverlay = true
            }
        }
        return presented
    }

    /// Return opens the action menu just inside the highlighted row, matching a click
    /// in the body of that row. The clip title stays visible above and beside it.
    private func actionMenuAnchor(over item: NSMenuItem) -> NSPoint {
        let frame = item.accessibilityFrame()
        guard frame.width > 0, frame.height > 0 else { return NSEvent.mouseLocation }
        return NSPoint(x: frame.minX + 48, y: frame.maxY - 12)
    }

    @MainActor
    private func actionMenuItem(at point: NSPoint, in menu: NSMenu?) -> NSMenuItem? {
        // The event tap runs before AppKit updates its highlight. Hit-test the
        // actual click so a quick modifier-click cannot fall through and close
        // the root menu, or apply an action to a previously highlighted clip.
        for item in menu?.items ?? [] {
            if let nested = actionMenuItem(at: point, in: item.submenu) { return nested }
            let frame = item.accessibilityFrame()
            if !frame.isEmpty, frame.contains(point) { return item }
        }
        return nil
    }

    private func actionDebugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        fputs("[ClipMenu] action: \(message())\n", stderr)
        #endif
    }

    @MainActor
    fileprivate func handleGlobalActionMouseUp(rightButton: Bool = false) -> Bool {
        if rightButton {
            guard suppressNextRightMouseUpForActionOverlay else { return false }
            suppressNextRightMouseUpForActionOverlay = false
            return true
        }
        guard suppressNextMouseUpForActionOverlay else { return false }
        suppressNextMouseUpForActionOverlay = false
        return true
    }

    private func cgEventFlagsToModifierFlags(_ flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        return result
    }

    @MainActor
    @discardableResult
    private func presentActionMenuForHighlightedItemIfNeeded() -> Bool {
        guard let runtime, runtime.settings.enableAction else { return false }
        let item = lastHighlightedMenuItem
            ?? filterRootMenu?.highlightedItem
            ?? findHighlightedMenuItem(in: filterRootMenu)
        guard let item, let clip = actionTargetClip(from: item) else { return false }
        return presentActionMenu(for: clip, at: NSEvent.mouseLocation, runtime: runtime, from: item)
    }

    @MainActor
    @discardableResult
    private func presentActionMenu(for clip: ClipEntry, at screenPoint: NSPoint, runtime: AppRuntime, from item: NSMenuItem? = nil) -> Bool {
        guard let context = runtime.modelContainer?.mainContext else { return false }
        let roots = (try? context.fetch(FetchDescriptor<ActionNode>(
            predicate: #Predicate<ActionNode> { $0.parent == nil },
            sortBy: [SortDescriptor(\.sortIndex)]
        ))) ?? []
        let enabledRoots = roots.filter(\.isEnabled)
        let leaves = enabledLeafActions(from: enabledRoots)

        if runtime.settings.invokeActionImmediately,
           leaves.count == 1,
           let only = leaves.first {
            filterRootMenu?.cancelTracking()
            Task { @MainActor in
                let didApply = await runtime.actionService.perform(
                    action: only,
                    on: clip,
                    executionContext: .transformOnly
                )
                if didApply, only.actionName?.trimmingCharacters(in: CharacterSet(charactersIn: ":")) != "removeAction" {
                    await self.finishHotkeyActionPaste()
                }
            }
            return true
        }

        // Keep the clip popup visible behind a pointer-positioned action panel.
        // Its callback retains the clip and runs after native tracking closes.
        runtime.hotkeyService.hidePreviewForActionMenu()
        ActionOverlayPresenter.shared.show(
            roots: enabledRoots,
            at: screenPoint,
            replacing: filterRootMenu,
            attachedTo: item
        ) { [weak self] node in
            guard let self else { return }
            Task { @MainActor in
                let didApply = await runtime.actionService.perform(
                    action: node,
                    on: clip,
                    executionContext: .transformOnly
                )
                if didApply, node.actionName?.trimmingCharacters(in: CharacterSet(charactersIn: ":")) != "removeAction" {
                    await self.finishHotkeyActionPaste()
                }
            }
        }
        return true
    }

    private func findHighlightedMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        if let item = menu.highlightedItem {
            if let submenu = item.submenu, let nested = findHighlightedMenuItem(in: submenu) {
                return nested
            }
            return item
        }
        for child in menu.items {
            if let submenu = child.submenu, let nested = findHighlightedMenuItem(in: submenu) {
                return nested
            }
        }
        return nil
    }

    private func actionTargetClip(from item: NSMenuItem) -> ClipEntry? {
        if let clip = item.representedObject as? ClipEntry {
            return clip
        }
        if let snippet = item.representedObject as? Snippet {
            let mock = ClipEntry()
            mock.stringValue = snippet.content
            mock.types = ["public.utf8-plain-text"]
            return mock
        }
        return nil
    }

    private func enabledLeafActions(from roots: [ActionNode]) -> [ActionNode] {
        var leaves: [ActionNode] = []
        func walk(_ nodes: [ActionNode]) {
            for node in nodes where node.isEnabled {
                if node.isLeaf {
                    leaves.append(node)
                } else {
                    walk(Array(node.children))
                }
            }
        }
        walk(roots)
        return leaves
    }

    func selectClipEntry(_ clip: ClipEntry) {
        guard let runtime else { return }
        let pasteTarget = targetAppForPaste
        Task { @MainActor in
            let generation = HistoryErasure.generation
            reactivateTargetAppIfNeeded()
            // Allow menu interaction to settle before writing pasteboard.
            try? await Task.sleep(nanoseconds: Self.menuDismissSettleDelay)
            guard generation == HistoryErasure.generation else { return }
            guard await runtime.clipsService.select(clip, pasteImmediately: false) else { return }
            let copiedChangeCount = NSPasteboard.general.changeCount
            if runtime.settings.autoPasteAfterSelection {
                // Give AppKit a beat to finish foreground activation.
                try? await Task.sleep(nanoseconds: Self.reactivationSettleDelay)
                reactivateTargetAppIfNeeded()
                try? await Task.sleep(nanoseconds: Self.prePasteDelay)
                if let pasteTarget {
                    await pasteService.paste(expectedTarget: pasteTarget, expectedChangeCount: copiedChangeCount)
                }
            }
        }
    }

    @objc func selectSnippetMenuItem(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet, let runtime else { return }

        if ignoreNextClipSelectionForActionOverlay {
            ignoreNextClipSelectionForActionOverlay = false
            return
        }

        let wantsActions = runtime.settings.enableAction && isActionModifierHeld()
        let clickPoint = lastClickLocation ?? NSEvent.mouseLocation
        lastClickModifierFlags = []
        lastClickLocation = nil

        if wantsActions {
            let mockClip = ClipEntry()
            mockClip.stringValue = snippet.content
            mockClip.types = ["public.utf8-plain-text"]
            _ = MainActor.assumeIsolated {
                self.presentActionMenu(for: mockClip, at: clickPoint, runtime: runtime, from: sender)
            }
            return
        }
        selectSnippetModel(snippet)
    }

    func selectSnippetModel(_ snippet: Snippet) {
        guard let runtime else { return }
        let pasteTarget = targetAppForPaste
        Task { @MainActor in
            reactivateTargetAppIfNeeded()
            try? await Task.sleep(nanoseconds: Self.menuDismissSettleDelay)
            guard await runtime.clipsService.copyStringToPasteboard(snippet.content, pasteImmediately: false) else { return }
            let copiedChangeCount = NSPasteboard.general.changeCount
            if runtime.settings.autoPasteAfterSelection {
                try? await Task.sleep(nanoseconds: Self.reactivationSettleDelay)
                reactivateTargetAppIfNeeded()
                try? await Task.sleep(nanoseconds: Self.prePasteDelay)
                if let pasteTarget {
                    await pasteService.paste(expectedTarget: pasteTarget, expectedChangeCount: copiedChangeCount)
                }
            }
        }
    }

    @objc func clearHistory(_ sender: NSMenuItem) {
        guard let runtime else { return }
        Task { await runtime.clipsService.clearHistoryWithConfirmation() }
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
        if let targetAppForPaste {
            await pasteService.paste(expectedTarget: targetAppForPaste)
        }
    }

    @MainActor
    private func finishHotkeyActionPaste() async {
        let pasteTarget = targetAppForPaste
        let copiedChangeCount = NSPasteboard.general.changeCount
        reactivateTargetAppIfNeeded()
        try? await Task.sleep(nanoseconds: Self.reactivationSettleDelay)
        reactivateTargetAppIfNeeded()
        if runtime?.settings.autoPasteAfterSelection != false {
            if let pasteTarget {
                await pasteService.paste(expectedTarget: pasteTarget, expectedChangeCount: copiedChangeCount)
            }
        }
    }
}

extension HotkeyPopupActionTarget: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? ClipMenuSearchField,
              field === filterSearchField else { return }
        if !isFilterModeActive {
            isFilterModeActive = true
        }
        applyCurrentFilterQuery()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = filterSearchField, control === field else { return false }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveFilterFocusToMenuList(field: field)
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:))
            || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            toggleImagesOnlyFilter()
            return true
        }
        return false
    }
}

#if DEBUG
/// In-process driver for the real popup, modifier hook and action/paste pipeline.
/// Uses native row geometry and system input because external AX queries can
/// resolve the closed status-menu copy of a row instead of its visible popup.
@MainActor
private final class NativeActionMenuSmoke {
    private static var retained: NativeActionMenuSmoke?
    private let root: NSMenu
    private let clip: NSMenuItem?
    private let phase = ProcessInfo.processInfo.environment["CLIPMENU_ACTION_SMOKE_PHASE"] ?? "mouse"
    private var step = -1
    private var started = Date()
    private var pasteCount = 0
    private var pasteText = ""
    private var hoverAttempts = 0
    private var backgroundSelection: NSMenuItem?
    private var observer: NSObjectProtocol?
    private var shortcutCount = 0
    private var shortcutTap: CFMachPort?
    private var shortcutSource: CFRunLoopSource?
    private var footerPointer: NSPoint?
    private var footerRow: NSMenuItem?
    private var testsFooter: Bool { phase.hasPrefix("footer-") || phase == "status-footer" }

    init(menu: NSMenu) {
        root = menu
        clip = menu.items.first(where: { $0.title == "ClipMenu UI test paste" })
        if phase == "direct-mouse" { step = 1 }
        if testsFooter { step = 0 }
    }
    static func start(menu: NSMenu) {
        let driver = NativeActionMenuSmoke(menu: menu)
        retained = driver
        if driver.phase == "shortcuts" {
            // Catch the keys AFTER the production event taps. Swallow them here
            // so regression tests do not save screenshots or open system UI.
            driver.shortcutTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, type, event, _ in
                MainActor.assumeIsolated {
                    if type == .keyDown,
                       event.flags.contains([.maskCommand, .maskShift]),
                       [20, 21, 23].contains(event.getIntegerValueField(.keyboardEventKeycode)) {
                        NativeActionMenuSmoke.retained?.shortcutCount += 1
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                }
            }, userInfo: nil)
            guard let tap = driver.shortcutTap else { driver.fail("could not install downstream shortcut probe") }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            driver.shortcutSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        }
        driver.observer = NotificationCenter.default.addObserver(forName: PasteService.simulatedPasteNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                driver.pasteCount += 1
                driver.pasteText = note.userInfo?["string"] as? String ?? ""
            }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { driver.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func fail(_ message: String) -> Never {
        fputs("[NATIVE ACTION SMOKE] FAIL \(phase): \(message)\n", stderr)
        Darwin.exit(1)
    }
    private func require(_ value: Bool, _ message: String) {
        if !value { fail(message) }
    }
    private func item(_ title: String, in menu: NSMenu?) -> NSMenuItem? {
        for row in menu?.items ?? [] {
            if row.title == title { return row }
            if let found = item(title, in: row.submenu) { return found }
        }
        return nil
    }
    private func point(_ row: NSMenuItem) -> CGPoint {
        let actionFrame = ActionOverlayPresenter.shared.frame(for: row)
        let r = actionFrame.isEmpty ? row.accessibilityFrame() : actionFrame
        require(r.width > 0, "row has no visible frame: \(row.title)")
        return CGPoint(x: r.midX, y: NSScreen.screens[0].frame.maxY - r.midY)
    }
    private func mouse(_ type: CGEventType, row: NSMenuItem, flags: CGEventFlags = [], xOffset: CGFloat = 0) {
        var position = point(row)
        position.x += xOffset
        let isActionHover = type == .mouseMoved && !ActionOverlayPresenter.shared.frame(for: row).isEmpty
        if !isActionHover { CGWarpMouseCursorPosition(position) }
        let eventType: CGEventType = isActionHover && phase == "drag-hover" ? .leftMouseDragged : type
        let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: position, mouseButton: .left)!
        event.flags = flags
        if type == .mouseMoved {
            event.setIntegerValueField(.mouseEventDeltaX, value: 1)
            event.setIntegerValueField(.mouseEventDeltaY, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
    private func tick() {
        if Date().timeIntervalSince(started) > 15 {
            fail("timeout step=\(step), pasteCount=\(pasteCount), text=\(pasteText)")
        }
        if testsFooter { tickFooter(); return }
        guard let clip else {
            fail("fixture clip missing")
        }
        let presenter = ActionOverlayPresenter.shared
        switch step {
        case -1:
            // Start a real pointer traversal even if the preceding phase left
            // the cursor at exactly the center of this same fixture row.
            mouse(.mouseMoved, row: clip, xOffset: -40)
        case 0:
            mouse(.mouseMoved, row: clip)
        case 1:
            if phase != "direct-mouse" {
                // Input delivery during app activation is asynchronous. Keep
                // moving within the row until AppKit reports the hover, with
                // a bounded timeout rather than assuming one event is enough.
                if root.highlightedItem !== clip, hoverAttempts < 6 {
                    hoverAttempts += 1
                    mouse(.mouseMoved, row: clip, xOffset: hoverAttempts.isMultiple(of: 2) ? -30 : 30)
                    return
                }
                require(root.highlightedItem === clip, "clip did not receive mouse hover: highlighted=\(root.highlightedItem?.title ?? "nil") row=\(clip.accessibilityFrame()) cursor=\(NSEvent.mouseLocation) active=\(NSApp.isActive)")
            }
            if phase.hasSuffix("keyboard") {
                key(36, flags: .maskCommand)
            } else {
                mouse(.leftMouseDown, row: clip, flags: .maskCommand)
                mouse(.leftMouseUp, row: clip, flags: .maskCommand)
            }
        case 2:
            require(presenter.isVisible, "modifier activation did not open actions")
            require(clip.accessibilityFrame().width > 0, "main clip popup closed")
            require(pasteCount == 0, "modifier click pasted original clip")
            require(clip.submenu == nil, "action menu added a caret to the clip row")
            backgroundSelection = root.highlightedItem
            if let first = presenter.menu?.items.first {
                let actionFrame = presenter.frame(for: first)
                if phase.hasSuffix("keyboard") {
                    let row = clip.accessibilityFrame()
                    require(abs(actionFrame.minX - row.minX - 53) < 2 && abs(actionFrame.maxY - row.maxY + 17) < 2, "action menu did not open inset from the highlighted clip")
                } else {
                    let pointer = NSEvent.mouseLocation
                    require(abs(actionFrame.minX - pointer.x - 5) < 2 && abs(actionFrame.maxY - pointer.y + 5) < 2, "action menu did not open under the mouse")
                }
            }
            if phase == "shortcuts" {
                for code: CGKeyCode in [20, 21, 23] {
                    key(code, flags: [.maskCommand, .maskShift])
                    key(code, flags: [.maskCommand, .maskShift, .maskControl])
                }
            }
            else if phase == "escape" { key(53) }
            else if phase.hasSuffix("keyboard") {
                key(8) // c: Case
            } else {
                guard let folder = item("Case", in: presenter.menu) else { fail("Case missing") }
                mouse(.mouseMoved, row: folder)
            }
        case 3:
            if phase == "shortcuts" {
                require(shortcutCount == 6, "screenshot shortcuts did not pass through production event taps: \(shortcutCount)/6")
                require(presenter.isVisible && pasteCount == 0, "screenshot shortcut affected actions")
                presenter.dismiss()
                root.cancelTrackingWithoutAnimation()
                fputs("[NATIVE ACTION SMOKE] PASS shortcuts: all six screenshot combinations passed through\n", stderr)
                Darwin.exit(0)
            }
            if phase == "escape" {
                require(!presenter.isVisible && pasteCount == 0, "Escape did not cancel")
                fputs("[NATIVE ACTION SMOKE] PASS escape\n", stderr)
                Darwin.exit(0)
            }
            require(clip.accessibilityFrame().width > 0, "main popup closed during action navigation")
            require(root.highlightedItem === backgroundSelection, "action hover changed the background popup selection")
            if phase.hasSuffix("keyboard") { key(124); key(32) } // right, u
            else {
                guard let action = item("UPPERCASE", in: presenter.menu) else { fail("UPPERCASE missing") }
                mouse(.mouseMoved, row: action)
            }
        case 4:
            require(clip.accessibilityFrame().width > 0, "main popup closed before selection")
            require(root.highlightedItem === backgroundSelection, "submenu hover changed the background popup selection")
            if phase.hasSuffix("keyboard") { key(36) }
            else {
                guard let action = item("UPPERCASE", in: presenter.menu) else { fail("UPPERCASE missing") }
                mouse(.leftMouseDown, row: action)
                mouse(.leftMouseUp, row: action)
            }
        default:
            guard pasteCount > 0 else { return }
            require(pasteCount == 1, "action pasted more than once")
            require(pasteText == "CLIPMENU UI TEST PASTE", "wrong transformed clip: \(pasteText)")
            require(!presenter.isVisible, "action menu still tracking during paste")
            fputs("[NATIVE ACTION SMOKE] PASS \(phase): main popup retained; uppercase pasted once\n", stderr)
            Darwin.exit(0)
        }
        step += 1
    }

    private func tickFooter() {
        if let footerPointer, let footerRow {
            let actual = NSEvent.mouseLocation
            require(hypot(actual.x - footerPointer.x, actual.y - footerPointer.y) < 2,
                    "footer hover moved pointer from \(footerPointer) to \(actual)")
            if root.highlightedItem !== footerRow, hoverAttempts < 6 {
                hoverAttempts += 1
                mouse(.mouseMoved, row: footerRow)
                return
            }
            require(root.highlightedItem === footerRow, "footer row did not stay highlighted: \(footerRow.title)")
        }
        let titles = ["Edit Snippets…", "Preferences…", "Quit \(AppDistribution.displayName)"]
        guard step < titles.count else {
            require(pasteCount == 0, "hover activated a clip")
            root.cancelTrackingWithoutAnimation()
            fputs("[NATIVE ACTION SMOKE] PASS \(phase): pointer stayed on every footer row\n", stderr)
            Darwin.exit(0)
        }
        guard let row = root.items.first(where: { $0.title == titles[step] }) else { fail("footer row missing") }
        let position = point(row)
        footerPointer = NSPoint(x: position.x, y: NSScreen.screens[0].frame.maxY - position.y)
        footerRow = row
        hoverAttempts = 0
        mouse(.mouseMoved, row: row)
        step += 1
    }
}
#endif
