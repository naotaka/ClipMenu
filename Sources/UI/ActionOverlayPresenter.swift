import AppKit

struct ActionOverlayItem: Equatable {
    var id: String
    var title: String
    var isLeaf: Bool
    var children: [ActionOverlayItem]
    init(id: String = UUID().uuidString, title: String, isLeaf: Bool, children: [ActionOverlayItem] = []) {
        self.id = id; self.title = title; self.isLeaf = isLeaf; self.children = children
    }
}

/// Pointer-positioned panels above the still-tracking native clipboard menu.
/// A single input router handles mouse and keyboard throughout the action tree.
@MainActor
final class ActionOverlayPresenter: NSObject {
    static let shared = ActionOverlayPresenter()
    private(set) var menu: NSMenu?
    private weak var parentMenu: NSMenu?
    private var columns: [ActionMenuColumn] = []
    private var openingTimer: Timer?
    private var presentationID = 0
    private var suppressMouseUp = false
    private var pendingClick: NSMenuItem?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var eventObserver: CFRunLoopObserver?
    private var isDraining = false
    private var typePrefix = ""
    private var lastTypeTime = Date.distantPast
    private static let typeAheadCharacters = CharacterSet.alphanumerics
        .union(.punctuationCharacters).union(.symbols).union(.whitespaces)
    var isVisible: Bool { openingTimer != nil || !columns.isEmpty }
    var isRoutingInput: Bool { eventObserver != nil }

    func parentMenuDidClose() { dismiss() }

    func dismiss() {
        presentationID &+= 1
        openingTimer?.invalidate()
        openingTimer = nil
        for column in columns { column.panel.orderOut(nil) }
        columns.removeAll()
        parentMenu = nil
        menu = nil
        stopInputRoutingIfIdle()
    }

    func show(items: [ActionOverlayItem], at screenPoint: NSPoint,
              replacing parentMenu: NSMenu? = nil, attachedTo item: NSMenuItem? = nil,
              onPick: @escaping (ActionOverlayItem) -> Void) {
        dismiss()
        let root = makeMenu(items: items, onPick: onPick)
        menu = root
        self.parentMenu = parentMenu
        typePrefix = ""
        installInputRouting()
        // Creating windows inside a CGEvent tap can stall that tap. Return the
        // triggering click first, then present in the native menu's run loop.
        let requestID = presentationID
        let opening = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.presentationID == requestID, let root = self.menu else { return }
                self.openingTimer = nil
                self.addColumn(root, topLeft: screenPoint)
            }
        }
        openingTimer = opening
        RunLoop.main.add(opening, forMode: .common)
        RunLoop.main.add(opening, forMode: .eventTracking)
    }

    /// Screen geometry used by both input routing and on-screen regression tests.
    func frame(for item: NSMenuItem) -> NSRect {
        for column in columns {
            if let index = column.menu.items.firstIndex(where: { $0 === item }) {
                return column.frameForRow(index)
            }
        }
        return .zero
    }

    func highlightedItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let column = columns.first(where: { $0.menu === menu }),
              let index = column.selected else { return nil }
        return column.menu.items[index]
    }

    private func addColumn(_ menu: NSMenu, topLeft: NSPoint) {
        let column = ActionMenuColumn(menu: menu, topLeft: topLeft) { [weak self] item in
            self?.activate(item)
        }
        columns.append(column)
        column.panel.orderFrontRegardless()
    }

    private func closeColumns(after index: Int) {
        while columns.count > index + 1 { columns.removeLast().panel.orderOut(nil) }
    }

    private func select(_ index: Int, in level: Int, openFolder: Bool) {
        guard columns.indices.contains(level) else { return }
        let column = columns[level]
        guard column.menu.items.indices.contains(index) else { return }
        if column.selected != index {
            closeColumns(after: level)
            column.selected = index
            column.updateHighlight()
        }
        guard openFolder, let child = column.menu.items[index].submenu else { return }
        if columns.count > level + 1, columns[level + 1].menu === child { return }
        closeColumns(after: level)
        let row = column.frameForRow(index)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(row.origin) }) ?? NSScreen.main
        let width = ActionMenuColumn.width(for: child)
        let opensLeft = row.maxX + width + 4 > (screen?.visibleFrame.maxX ?? .greatestFiniteMagnitude)
        addColumn(child, topLeft: NSPoint(x: opensLeft ? column.panel.frame.minX - width - 3 : column.panel.frame.maxX + 3,
                                         y: row.maxY + ActionMenuColumn.padding))
    }

    private func hit(at point: NSPoint) -> (level: Int, row: Int)? {
        for level in columns.indices.reversed() {
            let column = columns[level]
            for row in column.menu.items.indices where column.frameForRow(row).contains(point) { return (level, row) }
        }
        return nil
    }

    private func hover(at point: NSPoint) {
        guard let hit = hit(at: point) else { return }
        select(hit.row, in: hit.level, openFolder: true)
    }

    private func activate(_ item: NSMenuItem) {
        guard item.isEnabled,
              let level = columns.firstIndex(where: { $0.menu === item.menu }),
              let row = item.menu?.items.firstIndex(where: { $0 === item }) else { return }
        if item.submenu != nil { select(row, in: level, openFolder: true); return }
        guard let selection = item.representedObject as? ActionItemBox else { return }
        let parent = parentMenu
        dismiss()
        parent?.cancelTrackingWithoutAnimation()
        // Default mode begins only after the native clipboard menu unwinds.
        let callback = Timer(timeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { selection.onPick(selection.item) }
        }
        RunLoop.main.add(callback, forMode: .default)
    }

    func routeEvent(_ type: CGEventType, event: CGEvent) -> Bool {
        guard isVisible || suppressMouseUp else { return false }
        let point = NSPoint(x: event.location.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - event.location.y)
        if type == .leftMouseUp, suppressMouseUp {
            suppressMouseUp = false
            defer { stopInputRoutingIfIdle() }
            let selected = pendingClick
            pendingClick = nil
            if let selected, frame(for: selected).contains(point) { activate(selected) }
            return true
        }
        guard !columns.isEmpty else { return false }
        if type == .mouseMoved || type == .leftMouseDragged {
            guard columns.contains(where: { $0.panel.frame.contains(point) }) else { return false }
            // Route the actual event location before swallowing it. Polling
            // NSEvent.mouseLocation loses movement suppressed by this router.
            hover(at: point)
            return true
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            suppressMouseUp = type == .leftMouseDown
            if let hit = hit(at: point) {
                let item = columns[hit.level].menu.items[hit.row]
                if type == .leftMouseDown, item.submenu == nil {
                    select(hit.row, in: hit.level, openFolder: false)
                    pendingClick = item
                } else { activate(item) }
            }
            else if !columns.contains(where: { $0.panel.frame.contains(point) }) {
                let parent = parentMenu
                dismiss()
                parent?.cancelTrackingWithoutAnimation()
            }
            return true
        }
        guard type == .keyDown else { return false }
        // System/app shortcuts must reach macOS, including Cmd-Shift-3/4/5
        // and their Control variants. Only plain menu navigation/type-ahead
        // belongs to this overlay.
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if [123, 124, 125, 126, 36, 76].contains(key) { typePrefix = "" }
        let level = columns.count - 1
        let column = columns[level]
        switch key {
        case 53: dismiss()
        case 123:
            if level > 0 { closeColumns(after: level - 1) } else { dismiss() }
        case 124, 36, 76:
            if let index = column.selected {
                let item = column.menu.items[index]
                if item.submenu != nil {
                    select(index, in: level, openFolder: true)
                    if columns.count > level + 1 { select(0, in: level + 1, openFolder: false) }
                } else if key != 124 { activate(item) }
            } else if !column.menu.items.isEmpty { select(0, in: level, openFolder: false) }
        case 125, 126:
            let count = column.menu.items.count
            guard count > 0 else { return true }
            let current = column.selected ?? (key == 125 ? -1 : 0)
            select((current + (key == 125 ? 1 : count - 1)) % count, in: level, openFolder: false)
        default:
            guard let text = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
                  !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ Self.typeAheadCharacters.contains($0) }) else { return false }
            if Date().timeIntervalSince(lastTypeTime) > 0.7 { typePrefix = "" }
            typePrefix += text.lowercased()
            lastTypeTime = Date()
            if let index = column.menu.items.firstIndex(where: { $0.title.lowercased().hasPrefix(typePrefix) }) {
                select(index, in: level, openFolder: false)
            }
        }
        return true
    }

    private func installInputRouting() {
        let noTap = ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"
            && ProcessInfo.processInfo.environment["CLIPMENU_ACTION_SMOKE_PHASE"]?.hasPrefix("no-tap-") == true
        if eventTap == nil, !noTap, AppDistribution.usesAccessibility {
            let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown]
            let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, _ in
                MainActor.assumeIsolated {
                    let presenter = ActionOverlayPresenter.shared
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        // Disabling the tap on purpose also arrives as tapDisabledByUserInput.
                        // Turn it back on only while the menu is up or a closing click is unfinished.
                        if presenter.isVisible || presenter.suppressMouseUp, let tap = presenter.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    return presenter.routeEvent(type, event: event) ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: nil)
            if let eventTap {
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
                eventSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
            }
        }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        guard eventObserver == nil else { return }
        eventObserver = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeSources.rawValue, true, -10) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, (self.isVisible || self.suppressMouseUp), !self.isDraining else { return }
                self.isDraining = true
                defer { self.isDraining = false }
                var repost: [NSEvent] = []
                while let event = NSApp.nextEvent(matching: [.mouseMoved, .leftMouseDragged, .keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown], until: .distantPast, inMode: RunLoop.current.currentMode ?? .default, dequeue: true) {
                    guard let cgEvent = event.cgEvent, self.routeEvent(cgEvent.type, event: cgEvent) else {
                        repost.append(event)
                        continue
                    }
                }
                for event in repost.reversed() { NSApp.postEvent(event, atStart: true) }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), eventObserver, .commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), eventObserver, CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
    }

    private func stopInputRoutingIfIdle() {
        // An outside mouse-down closes the panels before its matching mouse-up.
        // Keep routing only until that release has been consumed.
        guard !isVisible, !suppressMouseUp else { return }
        pendingClick = nil
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventObserver { CFRunLoopObserverInvalidate(eventObserver) }
        eventObserver = nil
    }

    private func makeMenu(items: [ActionOverlayItem], onPick: @escaping (ActionOverlayItem) -> Void) -> NSMenu {
        let menu = NSMenu(title: "Actions")
        menu.autoenablesItems = false
        for action in items {
            let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
            if action.isLeaf { item.representedObject = ActionItemBox(action, onPick: onPick) }
            else { item.submenu = makeMenu(items: action.children, onPick: onPick) }
            menu.addItem(item)
        }
        if items.isEmpty {
            let empty = NSMenuItem(title: "No actions configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        return menu
    }
}

@MainActor
private final class ActionMenuColumn {
    static let padding: CGFloat = 5
    static let rowHeight: CGFloat = 25
    let menu: NSMenu
    let panel: NSPanel
    var selected: Int?
    private var rows: [ActionMenuRow] = []
    static func width(for menu: NSMenu) -> CGFloat {
        let maxTitle = menu.items.map { ($0.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 13)]).width }.max() ?? 140
        return min(420, max(210, ceil(maxTitle) + 54))
    }
    init(menu: NSMenu, topLeft: NSPoint, onActivate: @escaping (NSMenuItem) -> Void) {
        self.menu = menu
        let width = Self.width(for: menu)
        let height = CGFloat(menu.items.count) * Self.rowHeight + 2 * Self.padding
        let screen = NSScreen.screens.first(where: { $0.frame.contains(topLeft) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: max(bounds.minX, min(topLeft.x, bounds.maxX - width)), y: max(bounds.minY, min(topLeft.y - height, bounds.maxY - height)), width: width, height: height)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        panel.setAccessibilityLabel("Clipboard actions")
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        panel.contentView = background
        for (index, item) in menu.items.enumerated() {
            let frame = NSRect(x: Self.padding, y: height - Self.padding - CGFloat(index + 1) * Self.rowHeight, width: width - 2 * Self.padding, height: Self.rowHeight)
            let row = ActionMenuRow(frame: frame, item: item, onActivate: onActivate)
            background.addSubview(row)
            rows.append(row)
        }
    }
    func frameForRow(_ index: Int) -> NSRect { panel.convertToScreen(rows[index].frame) }
    func updateHighlight() {
        for (index, row) in rows.enumerated() { row.menuSelected = index == selected }
    }
}

@MainActor
private final class ActionMenuRow: NSButton {
    let item: NSMenuItem
    private let onActivate: (NSMenuItem) -> Void
    private let label: NSTextField
    private let arrow: NSTextField
    var menuSelected = false { didSet { updateColors() } }
    init(frame: NSRect, item: NSMenuItem, onActivate: @escaping (NSMenuItem) -> Void) {
        self.item = item
        self.onActivate = onActivate
        label = NSTextField(labelWithString: item.title)
        arrow = NSTextField(labelWithString: item.submenu == nil ? "" : "›")
        super.init(frame: frame)
        title = ""
        isBordered = false
        target = self
        action = #selector(invoke)
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = .menuFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 9, y: 4, width: frame.width - 35, height: 18)
        arrow.font = .systemFont(ofSize: 17, weight: .medium)
        arrow.frame = NSRect(x: frame.width - 20, y: 2, width: 16, height: 22)
        addSubview(label)
        addSubview(arrow)
        setAccessibilityLabel(item.title)
        setAccessibilityRole(.menuItem)
        isEnabled = item.isEnabled
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { onActivate(item) }
    private func updateColors() {
        layer?.backgroundColor = menuSelected && item.isEnabled ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        let color: NSColor = !item.isEnabled ? .disabledControlTextColor : (menuSelected ? .selectedMenuItemTextColor : .labelColor)
        label.textColor = color
        arrow.textColor = color
    }
}

@MainActor
private final class ActionItemBox: NSObject {
    let item: ActionOverlayItem
    let onPick: (ActionOverlayItem) -> Void
    init(_ item: ActionOverlayItem, onPick: @escaping (ActionOverlayItem) -> Void) {
        self.item = item; self.onPick = onPick
    }
}
