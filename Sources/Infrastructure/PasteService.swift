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
    static let simulatedPasteNotification = Notification.Name("PasteService.simulatedPasteNotification")
    /// Configured by the app runtime; isolated service hosts only check permission.
    @MainActor static var authorizePaste: () -> Bool = { accessibilityStatus().isTrusted }

    private var cachedVKeyCode: CGKeyCode?
    private var loggedMissingAXThisSession = false
    private var inputSourceObserver: NSObjectProtocol?

    struct AccessibilityStatus {
        let isTrusted: Bool
        let bundleIdentifier: String
        let executablePath: String
    }

    private func observeInputSourceIfNeeded() {
        guard inputSourceObserver == nil else { return }
        inputSourceObserver = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.invalidateCachedKeyCode() }
        }
    }

    deinit {
        if let inputSourceObserver { NotificationCenter.default.removeObserver(inputSourceObserver) }
    }

    func paste(expectedTarget: NSRunningApplication? = nil, expectedChangeCount: Int? = nil) async {
        if !AppDistribution.usesAccessibility { return }
        if Self.isPasteUITestMode {
            await MainActor.run {
                let value = NSPasteboard.general.string(forType: .string) ?? ""
                NotificationCenter.default.post(
                    name: Self.simulatedPasteNotification,
                    object: nil,
                    userInfo: ["string": value]
                )
            }
            return
        }

        let request = await MainActor.run {
            (expectedTarget ?? NSWorkspace.shared.frontmostApplication,
             expectedChangeCount ?? NSPasteboard.general.changeCount)
        }
        guard let target = request.0, !target.isTerminated else {
            Self.log.error("Paste aborted: destination application is unavailable")
            return
        }

        let allowed = await MainActor.run {
            Self.authorizePaste()
        }
        guard allowed else {
            Self.log.info("Clip left on the clipboard for the user to paste")
            return
        }
        guard isAccessibilityTrusted() else {
            Self.log.error("Paste aborted: Accessibility permission not granted")
            return
        }
        guard let keyCode = await resolvedVKeyCode() else {
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

        await MainActor.run {
            guard !target.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  NSPasteboard.general.changeCount == request.1 else {
                Self.log.error("Paste aborted: destination or clipboard changed")
                return
            }
            // Address the selected process directly so a focus change after
            // this check cannot redirect a global Cmd+V to another app.
            keyDown?.postToPid(target.processIdentifier)
            keyUp?.postToPid(target.processIdentifier)
            Self.log.info("Posted Cmd+V events using keyCode=\(keyCode, privacy: .public)")
        }
    }

    nonisolated static func accessibilityStatus() -> AccessibilityStatus {
        AccessibilityStatus(
            isTrusted: isPasteUITestMode ? true : (AppDistribution.usesAccessibility && AXIsProcessTrusted()),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "<nil>",
            executablePath: Bundle.main.executableURL?.path ?? "<unknown>"
        )
    }

    /// Shows the system Accessibility prompt. Call only after the in-app explanation.
    @discardableResult
    nonisolated static func requestAccessibilityPermissionIfNeeded() -> Bool {
        if !AppDistribution.usesAccessibility { return false }
        if isPasteUITestMode { return true }
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated private static var isPasteUITestMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"
        #else
        false
        #endif
    }

    private func isAccessibilityTrusted() -> Bool {
        if Self.accessibilityStatus().isTrusted {
            return true
        }

        if !loggedMissingAXThisSession {
            loggedMissingAXThisSession = true
            let status = Self.accessibilityStatus()
            Self.log.error("Accessibility permission missing. bundleID=\(status.bundleIdentifier, privacy: .public) execPath=\(status.executablePath, privacy: .public)")
        }
        return false
    }

    private func invalidateCachedKeyCode() {
        cachedVKeyCode = nil
    }

    /// HIToolbox input-source APIs must run on the main thread.
    private func resolvedVKeyCode() async -> CGKeyCode? {
        observeInputSourceIfNeeded()
        if let cachedVKeyCode {
            return cachedVKeyCode
        }
        let code = await MainActor.run {
            Self.lookupVKeyCodeFromCurrentLayout()
        }
        cachedVKeyCode = code
        return code
    }

    @MainActor
    private static func lookupVKeyCodeFromCurrentLayout() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return 9
        }

        let layout = unsafeBitCast(layoutData, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layout) else {
            return 9
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
                return CGKeyCode(keyCode)
            }
        }

        return 9
    }
}
