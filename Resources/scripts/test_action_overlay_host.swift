import AppKit
import SwiftData

@main
enum ActionMenuSmokeMain {
    static func main() {
        let app = NSApplication.shared
        let host = SmokeHost()
        app.delegate = host
        app.setActivationPolicy(.regular)
        app.run()
    }
}

/// Uses real NSMenu tracking and queued input, plus focused event-routing checks.
@MainActor
final class SmokeHost: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let presenter = ActionOverlayPresenter.shared
    private var rootClosed = false
    private var rootReturned = false
    private var rootActivated = false
    private var picked: [String] = []
    private var stage = 0
    private var container: ModelContainer!
    private var transformed = false
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
    private var window: NSWindow!
    private var lastStep = Date()
    private var deadline = Date()
    private let phase = ProcessInfo.processInfo.environment["ACTION_OVERLAY_SMOKE_PHASE"] ?? "mouse"
    private let items = [
        ActionOverlayItem(title: "Plain Text", isLeaf: true),
        ActionOverlayItem(title: "Case", isLeaf: false, children: [
            ActionOverlayItem(title: "lowercase", isLeaf: true),
            ActionOverlayItem(title: "Nested", isLeaf: false, children: [
                ActionOverlayItem(title: "UPPERCASE", isLeaf: true)
            ])
        ]),
        ActionOverlayItem(title: "Trim", isLeaf: true)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let schema = Schema([ClipEntry.self, ActionNode.self])
        container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        window = NSWindow(contentRect: NSRect(x: 250, y: 600, width: 400, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Action smoke paste target"
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        let main = NSMenu()
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
        NSApp.activate(ignoringOtherApps: true)
        deadline = Date().addingTimeInterval(10)
        let driver = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(driver, forMode: .common)
        RunLoop.main.add(driver, forMode: .eventTracking)

        let root = NSMenu(title: "Clips")
        root.delegate = self
        let row = NSMenuItem(title: "Alpha clip", action: #selector(activateClip), keyEquivalent: "")
        row.target = self
        root.addItem(row)
        let handoff = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.presenter.show(items: self.items, at: NSPoint(x: 700, y: 650), replacing: self.rootMenu, attachedTo: self.rootMenu?.items.first) { item in
                    self.check(self.rootReturned, "action ran before clip menu returned")
                    self.check(!self.presenter.isVisible, "action ran before action tracking returned")
                    self.picked.append(item.title)
                    Task { @MainActor in
                        let context = self.container.mainContext
                        let clip = ClipEntry()
                        clip.stringValue = "ClipMenu action Test"
                        context.insert(clip)
                        let action = ActionNode(title: "UPPERCASE", isLeaf: true)
                        action.actionType = "javaScript"
                        action.scriptPath = "/old/build/ClipMenu.app/Contents/Resources/scripts/action/Case/UPPERCASE.js"
                        context.insert(action)
                        let service = ActionService()
                        await service.start(context: context)
                        let applied = await service.perform(action: action, on: clip, executionContext: .transformOnly)
                        self.check(applied, "relocated script did not execute")
                        self.check(NSPasteboard.general.string(forType: .string) == "CLIPMENU ACTION TEST", "script did not transform the selected clip")
                        let legacy = ActionNode(title: "Plain", isLeaf: true)
                        legacy.actionType = "builtin"
                        legacy.actionName = "pasteAsPlainText:"
                        context.insert(legacy)
                        let plain = await service.perform(action: legacy, on: clip, executionContext: .transformOnly)
                        self.check(plain && NSPasteboard.general.string(forType: .string) == clip.stringValue, "legacy selector name failed")
                        _ = await service.perform(action: action, on: clip, executionContext: .transformOnly)
                        self.window.makeKeyAndOrderFront(nil)
                        self.window.makeFirstResponder(self.textView)
                        NSApp.activate(ignoringOtherApps: true)
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        self.check(NSApp.isActive && self.window.isKeyWindow, "paste target was not activated: active=\(NSApp.isActive), key=\(NSApp.keyWindow?.title ?? "nil"), front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"), visible=\(self.window.isVisible)")
                        self.transformed = true
                        await PasteService().paste()
                    }
                }
            }
        }
        rootMenu = root
        RunLoop.main.add(handoff, forMode: .eventTracking)
        root.popUp(positioning: nil, at: NSPoint(x: 700, y: 650), in: nil)
        rootReturned = true
    }

    private var rootMenu: NSMenu?
    @objc private func activateClip() { rootActivated = true }
    func menuDidClose(_ menu: NSMenu) { rootClosed = true }

    private func step() {
        if Date() > deadline { fail("timeout at stage \(stage), rootClosed=\(rootClosed), rootReturned=\(rootReturned), picked=\(picked), transformed=\(transformed), pasted=\(textView.string), AX=\(PasteService.accessibilityStatus().isTrusted)") }
        guard Date().timeIntervalSince(lastStep) > 0.5 else { return }
        if stage == 0 {
            guard presenter.isVisible else { return }
            check(!rootClosed && !rootReturned, "clip menu closed before an action was selected")
            check(!rootActivated && picked.isEmpty, "handoff selected a clip or action")
            check(rootMenu?.items.first?.submenu == nil, "action menu added a caret to the clip row")
            let first = presenter.frame(for: row("Plain Text"))
            check(abs(first.minX - 705) < 2 && abs(first.maxY - 645) < 2, "action menu is not at the requested pointer position")
        }
        if phase == "shortcuts" {
            for code: CGKeyCode in [20, 21, 23] { // macOS screenshot shortcuts: 3, 4, 5.
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
                event.flags = [.maskCommand, .maskShift]
                check(!presenter.routeEvent(.keyDown, event: event), "captured Command-Shift screenshot shortcut")
                event.flags.insert(.maskControl)
                check(!presenter.routeEvent(.keyDown, event: event), "captured screenshot-to-clipboard shortcut")
            }
            check(presenter.isVisible && picked.isEmpty, "system shortcut changed action selection")
            presenter.dismiss()
            pass()
        }
        if phase == "event-routing" {
            // Deliberately leave the system cursor elsewhere: delivery must
            // use the event, not a later poll of the cursor's global position.
            for title in ["Case", "Nested", "UPPERCASE"] {
                let item = row(title)
                let p = center(item)
                let point = CGPoint(x: p.x, y: NSScreen.screens[0].frame.maxY - p.y)
                let type: CGEventType = title == "Nested" ? .leftMouseDragged : .mouseMoved
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
                check(presenter.routeEvent(type, event: event), "hover event was passed to the main popup")
                check(presenter.highlightedItem(in: item.menu) === item, "hover event did not immediately select \(title)")
            }
            presenter.dismiss()
            pass()
        }
        if phase == "reopen" {
            switch stage {
            case 0:
                presenter.dismiss()
                check(!presenter.isRoutingInput, "closed menu still routing input")
                presenter.show(items: items, at: NSPoint(x: 700, y: 650), replacing: rootMenu) { _ in }
            case 1: move(to: row("Case"))
            default:
                check(presenter.highlightedItem(in: presenter.menu)?.title == "Case", "reopened menu did not resume hover routing")
                presenter.dismiss()
                pass()
            }
        }
        else if phase == "mouse" || phase == "event-hover" { mouseStep() }
        else if phase == "keyboard" { keyboardStep() }
        else if phase == "escape" {
            if stage == 0 { key(53, "\u{1b}") }
            else {
                check(!presenter.isVisible && picked.isEmpty, "Escape did not cancel without picking")
                pass()
            }
        } else if phase == "outside" {
            if stage == 0 { click(NSPoint(x: 400, y: 400)) }
            else {
                check(!presenter.isVisible && picked.isEmpty, "outside click did not cancel")
                pass()
            }
        }
        stage += 1
        lastStep = Date()
    }

    private func mouseStep() {
        switch stage {
        case 0: move(to: row("Case"))
        case 1:
            check(presenter.highlightedItem(in: presenter.menu)?.title == "Case", "mouse did not highlight Case: highlighted=\(presenter.highlightedItem(in: presenter.menu)?.title ?? "nil"), frame=\(presenter.frame(for: row("Case"))), cursor=\(NSEvent.mouseLocation), active=\(NSApp.isActive), AX=\(PasteService.accessibilityStatus().isTrusted)")
            move(to: row("Nested"))
        case 2:
            check(presenter.highlightedItem(in: row("Case").submenu)?.title == "Nested", "mouse did not enter submenu")
            move(to: row("UPPERCASE"))
        case 3:
            check(presenter.highlightedItem(in: row("Nested").submenu)?.title == "UPPERCASE", "mouse did not enter nested submenu")
            click(center(row("UPPERCASE")))
        default:
            guard transformed, textView.string == "CLIPMENU ACTION TEST" else { return }
            check(picked == ["UPPERCASE"] && !presenter.isVisible, "nested click did not pick exactly once: \(picked)")
            pass()
        }
    }

    private func keyboardStep() {
        switch stage {
        case 0:
            key(35, "p") // Type-select Plain Text.
        case 1:
            check(presenter.highlightedItem(in: presenter.menu)?.title == "Plain Text", "keyboard did not select Plain Text (highlight=\(presenter.highlightedItem(in: presenter.menu)?.title ?? "nil"))")
            key(125, "\u{f701}") // Down: Case
        case 2:
            check(presenter.highlightedItem(in: presenter.menu)?.title == "Case", "Down did not select Case")
            key(124, "\u{f703}") // Right: open Case
        case 3:
            check(presenter.highlightedItem(in: row("Case").submenu)?.title == "lowercase", "Right did not enter Case")
            key(125, "\u{f701}")
        case 4: key(124, "\u{f703}") // Right: Nested
        case 5:
            check(presenter.highlightedItem(in: row("Nested").submenu)?.title == "UPPERCASE", "Right did not enter nested submenu")
            key(123, "\u{f702}") // Left: return to Case
        case 6:
            check(presenter.highlightedItem(in: row("Case").submenu)?.title == "Nested", "Left lost parent selection")
            key(124, "\u{f703}")
        case 7: key(36, "\r")
        default:
            guard transformed, textView.string == "CLIPMENU ACTION TEST" else { return }
            check(picked == ["UPPERCASE"] && !presenter.isVisible, "Return did not pick exactly once: \(picked)")
            pass()
        }
    }

    private func row(_ title: String) -> NSMenuItem {
        func find(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.title == title { return item }
                if let match = find(item.submenu) { return match }
            }
            return nil
        }
        guard let item = find(presenter.menu) else { fail("missing row \(title)") }
        return item
    }

    private func center(_ item: NSMenuItem) -> NSPoint {
        let frame = presenter.frame(for: item)
        check(frame.width > 0 && frame.height > 0, "row not visible: \(item.title), \(frame)")
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private func move(to item: NSMenuItem) {
        let point = center(item)
        let screenHeight = NSScreen.screens[0].frame.maxY
        if phase != "event-hover" {
            CGWarpMouseCursorPosition(CGPoint(x: point.x, y: screenHeight - point.y))
        }
        postMouse(.mouseMoved, at: point)
    }

    private func click(_ point: NSPoint) {
        postMouse(.leftMouseDown, at: point)
        postMouse(.leftMouseUp, at: point)
    }

    private func postMouse(_ type: NSEvent.EventType, at point: NSPoint) {
        let cgType: CGEventType = type == .mouseMoved ? .mouseMoved : (type == .leftMouseDown ? .leftMouseDown : .leftMouseUp)
        let q = CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
        let event = CGEvent(mouseEventSource: nil, mouseType: cgType, mouseCursorPosition: q, mouseButton: .left)!
        event.flags = []
        if type == .mouseMoved {
            event.setIntegerValueField(.mouseEventDeltaX, value: 1)
            event.setIntegerValueField(.mouseEventDeltaY, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    private func key(_ code: UInt16, _ characters: String) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    private func check(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }
    private func fail(_ message: String) -> Never {
        fputs("[ACTION MENU SMOKE] FAIL \(phase): \(message)\n", stderr)
        Darwin.exit(1)
    }
    private func pass() -> Never {
        check(!presenter.isRoutingInput, "input routing stayed active after dismissal")
        fputs("[ACTION MENU SMOKE] PASS \(phase)\n", stderr)
        Darwin.exit(0)
    }
}
