import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ScriptError: Error, CustomStringConvertible {
    let description: String
}

func runRealPreviewTest() throws {
    guard CommandLine.arguments.count >= 2 else {
        throw ScriptError(description: "Usage: test_real_preview.swift /path/to/ClipMenu.app")
    }

    let appPath = CommandLine.arguments[1]
    let appURL = URL(fileURLWithPath: appPath)

    guard let bundle = Bundle(url: appURL),
          let executableURL = bundle.executableURL,
          let bundleID = bundle.bundleIdentifier
    else {
        throw ScriptError(description: "Could not resolve bundle for \(appPath)")
    }

    print("[REAL TEST] Terminating existing instances of \(bundleID)...")
    for runningApp in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        runningApp.forceTerminate()
    }
    Thread.sleep(forTimeInterval: 0.5)

    print("[REAL TEST] Launching real ClipMenu app (WITHOUT test mode mocks)...")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--seed-clips", "--open-hotkey-menu"]
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "CLIPMENU_UI_TEST_MODE")
    process.environment = env
    process.standardError = FileHandle.standardError
    process.standardOutput = FileHandle.standardOutput
    try process.run()

    let pid = process.processIdentifier
    print("[REAL TEST] ClipMenu launched with PID \(pid)")

    // Activate app so it receives keyboard events
    if let runningApp = NSRunningApplication(processIdentifier: pid) {
        runningApp.activate(options: .activateIgnoringOtherApps)
    }
    Thread.sleep(forTimeInterval: 0.5)

    // Menu opens via --open-hotkey-menu after 300ms. Wait for it to open and settle.
    Thread.sleep(forTimeInterval: 1.0)
    print("[REAL TEST] Pressing Up Arrow once...")
    sendKeyDownUp(keyCode: 126, pid: pid) // Up Arrow
    Thread.sleep(forTimeInterval: 2.0)

    print("[REAL TEST] Inspecting on-screen windows for PID \(pid)...")
    var foundPreviewFrame: CGRect? = nil
    var foundLayer: Int = 0

    let start = Date()
    while Date().timeIntervalSince(start) < 3.0 {
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windowList {
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                      let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
                else { continue }

                let layer = info[kCGWindowLayer as String] as? Int ?? 0
                let name = info[kCGWindowName as String] as? String ?? ""
                print("   -> Found PID \(pid) Window: '\(name)', layer=\(layer), frame=\(NSStringFromRect(rect))")

                if (layer == 1000 || layer == 3 || layer == 101) && rect.width > 50 && rect.height > 20 && rect.height < 800 {
                    foundPreviewFrame = rect
                    foundLayer = layer
                    break
                }
            }
        }
        if foundPreviewFrame != nil { break }
        Thread.sleep(forTimeInterval: 0.2)
    }

    // Clean up menu
    sendKeyDownUp(keyCode: 53, pid: pid) // Escape
    Thread.sleep(forTimeInterval: 0.2)
    process.terminate()

    if let frame = foundPreviewFrame {
        print("[REAL TEST] PASS: Real preview window DETECTED on screen! Frame: \(NSStringFromRect(frame)), Layer: \(foundLayer)")
    } else {
        throw ScriptError(description: "FAIL: Real preview window was NOT detected on screen!")
    }
}

func sendCmdShiftV() {
    let src = CGEventSource(stateID: .combinedSessionState)
    // Keycode 9 = 'v'
    guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
          let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
    else { return }

    down.flags = [.maskCommand, .maskShift]
    up.flags = [.maskCommand, .maskShift]

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func sendKeyDownUp(keyCode: CGKeyCode, pid: pid_t) {
    let src = CGEventSource(stateID: .combinedSessionState)
    guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
    else { return }

    down.postToPid(pid)
    Thread.sleep(forTimeInterval: 0.05)
    up.postToPid(pid)
}

do {
    try runRealPreviewTest()
} catch {
    print("[REAL TEST] \(error)")
    exit(1)
}
