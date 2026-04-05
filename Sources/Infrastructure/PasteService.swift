import CoreGraphics
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Synthesises a Cmd+V key event to paste the current pasteboard contents
/// into the frontmost application.
///
/// Requires Accessibility permission (`AXIsProcessTrusted()`).  The legacy
/// implementation lives in `legacy/Source/AppController.m -pasteFromClipboard`.
actor PasteService {
    private static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "PasteService")
    private var cachedVKeyCode: CGKeyCode?
    private var loggedMissingAXThisSession = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.invalidateCachedKeyCode() }
        }
    }

    func paste() async {
        guard isAccessibilityTrusted() else {
            Self.log.error("Paste aborted: Accessibility permission not granted")
            return
        }
        guard let keyCode = vKeyCode() else {
            Self.log.error("Paste aborted: could not resolve V key code")
            return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Self.log.error("Paste aborted: could not create CGEventSource")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        Self.log.info("Posted Cmd+V events using keyCode=\(keyCode, privacy: .public)")
    }

    private func isAccessibilityTrusted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        // Avoid OS permission prompts on launch/session boundaries. We only
        // report missing permission and let users grant it from Settings.
        if !loggedMissingAXThisSession {
            loggedMissingAXThisSession = true
            let bundleID = Bundle.main.bundleIdentifier ?? "<nil>"
            let execPath = Bundle.main.executableURL?.path ?? "<unknown>"
            Self.log.error("Accessibility permission missing. bundleID=\(bundleID, privacy: .public) execPath=\(execPath, privacy: .public)")
        }

        return false
    }

    private func invalidateCachedKeyCode() {
        cachedVKeyCode = nil
    }

    private func vKeyCode() -> CGKeyCode? {
        if let cachedVKeyCode {
            return cachedVKeyCode
        }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            cachedVKeyCode = 9
            return cachedVKeyCode
        }

        let layout = unsafeBitCast(layoutData, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layout) else {
            cachedVKeyCode = 9
            return cachedVKeyCode
        }

        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(bytes))

        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &length,
                &chars
            )

            guard status == noErr, length > 0 else { continue }
            let mapped = String(utf16CodeUnits: chars, count: Int(length))
            if mapped.caseInsensitiveCompare("v") == .orderedSame {
                cachedVKeyCode = CGKeyCode(keyCode)
                return cachedVKeyCode
            }
        }

        cachedVKeyCode = 9
        return cachedVKeyCode
    }
}
