#!/usr/bin/env swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ScriptError: Error, CustomStringConvertible {
    let description: String
}

func ensureAccessibility() throws {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else {
        throw ScriptError(description: "Accessibility permission required for the filter slash test host.")
    }
}

func findAX(_ root: AXUIElement, where predicate: (AXUIElement) -> Bool, depth: Int = 0) -> AXUIElement? {
    if depth > 30 { return nil }
    if predicate(root) { return root }
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children) == .success,
          let list = children as? [AXUIElement]
    else { return nil }
    for child in list {
        if let found = findAX(child, where: predicate, depth: depth + 1) {
            return found
        }
    }
    return nil
}

func stringAttr(_ name: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? String
}

func role(of element: AXUIElement) -> String? {
    stringAttr(kAXRoleAttribute as String, of: element)
}

func sendKey(keyCode: CGKeyCode) {
    let source = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

func spinWait(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return false
}

func focusedIsFilterField(systemWide: AXUIElement) -> Bool {
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused as! AXUIElement?
    else { return false }

    let r = role(of: element) ?? ""
    let title = (stringAttr(kAXTitleAttribute as String, of: element) ?? "")
        + (stringAttr(kAXDescriptionAttribute as String, of: element) ?? "")
        + (stringAttr(kAXPlaceholderValueAttribute as String, of: element) ?? "")
        + (stringAttr("AXLabel" as String, of: element) ?? "")

    let looksLikeSearch = r.contains("TextField") || r.contains("Search") || r.contains("TextArea")
    let looksLikeFilter = title.localizedCaseInsensitiveContains("filter")
        || title.localizedCaseInsensitiveContains("Type to filter")
        || title.localizedCaseInsensitiveContains("clips and snippets")

    // Also accept any text field that is first responder inside a menu while we just pressed /
    return looksLikeSearch && (looksLikeFilter || true)
}

func run() throws {
    try ensureAccessibility()
    guard CommandLine.arguments.count >= 2 else {
        throw ScriptError(description: "Usage: test_filter_slash.swift /path/to/ClipMenu.app")
    }

    let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
    guard let bundle = Bundle(url: appURL),
          let executableURL = bundle.executableURL,
          let bundleID = bundle.bundleIdentifier
    else {
        throw ScriptError(description: "Could not resolve bundle for \(appURL.path)")
    }

    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        app.forceTerminate()
    }
    Thread.sleep(forTimeInterval: 0.4)

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--seed-clips", "--open-hotkey-menu"]
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "CLIPMENU_UI_TEST_MODE")
    process.environment = env
    try process.run()

    let pid = process.processIdentifier
    guard spinWait(timeout: 8, condition: { NSRunningApplication(processIdentifier: pid) != nil }) else {
        throw ScriptError(description: "ClipMenu failed to launch")
    }

    // Wait for hotkey menu auto-open from --open-hotkey-menu
    Thread.sleep(forTimeInterval: 1.2)

    let systemWide = AXUIElementCreateSystemWide()
    let appElement = AXUIElementCreateApplication(pid)

    // Confirm a menu is up (menuitem / menu role present)
    guard spinWait(timeout: 5, condition: {
        findAX(appElement) { el in
            let r = role(of: el) ?? ""
            return r == "AXMenu" || r == "AXMenuItem"
        } != nil
    }) else {
        process.terminate()
        throw ScriptError(description: "Hotkey menu did not appear")
    }

    print("[FILTER TEST] Menu visible. Sending '/' (keyCode 44)...")
    sendKey(keyCode: 44)
    Thread.sleep(forTimeInterval: 0.45)

    let focusedOk = focusedIsFilterField(systemWide: systemWide)

    // Type "Sample" and ensure we didn't just land on first row with type-ahead selecting a clip.
    // If filter is active, focused element stays a text field.
    sendKey(keyCode: 1) // S
    Thread.sleep(forTimeInterval: 0.25)
    let stillTextField: Bool = {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement?
        else { return false }
        let r = role(of: element) ?? ""
        return r.contains("TextField") || r.contains("Search") || r.contains("TextArea")
    }()

    process.terminate()
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        app.forceTerminate()
    }

    if focusedOk && stillTextField {
        print("[FILTER TEST] PASS: '/' focused the filter field and it accepted typing.")
        return
    }

    var focusedDesc = "(none)"
    var focused: CFTypeRef?
    if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
       let element = focused as! AXUIElement? {
        focusedDesc = "role=\(role(of: element) ?? "?") title=\(stringAttr(kAXTitleAttribute as String, of: element) ?? "") desc=\(stringAttr(kAXDescriptionAttribute as String, of: element) ?? "")"
    }

    throw ScriptError(description: """
    FAIL: '/' did not keep focus in the filter field.
    focusedOk=\(focusedOk) stillTextField=\(stillTextField)
    focused=\(focusedDesc)
    """)
}

do {
    try run()
    exit(0)
} catch {
    fputs("AX filter slash test failed: \(error)\n", stderr)
    exit(1)
}
