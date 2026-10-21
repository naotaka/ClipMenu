import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

struct ScenarioResult {
    let name: String
    let previewFrame: CGRect
    let referenceFrame: CGRect
    let allMenuBounds: CGRect
}

private let pollInterval: TimeInterval = 0.05

struct PreviewAXSmokeRunner {
    static func run() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw SmokeFailure(description: "Usage: preview_ax_smoke.swift /path/to/ClipMenuTest.app")
        }

        guard ensureAutomationAccessibility() else {
            throw SmokeFailure(description: "Accessibility permission is required for the AX smoke runner. Approve the prompt for the automation host, then rerun the script.")
        }

        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let scenarios: [(String, (AutomationContext) throws -> ScenarioResult)] = [
            ("status-preview", runStatusPreviewScenario),
            ("keyboard-preview", runKeyboardPreviewScenario),
            ("submenu-preview", runSubmenuPreviewScenario),
            ("status-submenu-preview", runStatusSubmenuPreviewScenario),
            ("scroll-preview", runScrollPreviewScenario),
        ]

        var results: [ScenarioResult] = []
        for (name, scenario) in scenarios {
            let context = try launchContext(appURL: appURL)
            defer { context.terminate() }
            let result = try scenario(context)
            results.append(result)
            print("PASS \(name): preview=\(NSStringFromRect(result.previewFrame)) ref=\(NSStringFromRect(result.referenceFrame))")
        }

        print("All preview AX smoke checks passed (\(results.count) scenarios).")
    }

    private static func launchContext(appURL: URL) throws -> AutomationContext {
        do {
            guard let bundle = Bundle(url: appURL),
                  let executableURL = bundle.executableURL,
                  let bundleIdentifier = bundle.bundleIdentifier
            else {
                throw SmokeFailure(description: "Could not resolve bundle metadata for \(appURL.path)")
            }

            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                app.forceTerminate()
            }

            let process = Process()
            process.executableURL = executableURL
            var environment = ProcessInfo.processInfo.environment
            environment["CLIPMENU_UI_TEST_MODE"] = "1"
            process.environment = environment
            try process.run()

            let pid = process.processIdentifier
            guard spinWait(timeout: 10, condition: {
                NSRunningApplication(processIdentifier: pid) != nil
            }) else {
                throw SmokeFailure(description: "Timed out waiting for \(bundleIdentifier) to launch")
            }

            let appElement = AXUIElementCreateApplication(pid)
            let systemWideElement = AXUIElementCreateSystemWide()
            guard spinWait(timeout: 10, condition: {
                findElement(in: appElement) { element in
                    stringAttribute(kAXTitleAttribute, of: element) == "Paste Integration"
                } != nil
            }) else {
                throw SmokeFailure(description: "Timed out waiting for the harness window")
            }

            return AutomationContext(
                bundleIdentifier: bundleIdentifier,
                process: process,
                appElement: appElement,
                systemWideElement: systemWideElement
            )
        } catch let error as SmokeFailure {
            throw error
        } catch {
            throw SmokeFailure(description: "Failed to launch automation context: \(error.localizedDescription)")
        }
    }

    private static func runStatusPreviewScenario(context: AutomationContext) throws -> ScenarioResult {
        try press(identifier: "openStatusPopupButton", in: context.appElement)
        let row = try waitForRectLabel(identifier: "selectedRootRowFrameLabel", in: context.appElement)
        moveMouse(to: convertToScreen(rect: row.frame, in: context.appElement).center)

        let previewFrame = try waitForRectLabel(identifier: "previewFrameLabel", in: context.appElement)
        let popupBounds = try waitForRectLabel(identifier: "rootPopupFrameLabel", in: context.appElement)

        try assertLeftPreview(
            previewFrame: previewFrame.frame,
            menuBounds: popupBounds.frame,
            referenceFrame: row.frame,
            scenario: "status-preview"
        )

        return ScenarioResult(
            name: "status-preview",
            previewFrame: previewFrame.frame,
            referenceFrame: row.frame,
            allMenuBounds: popupBounds.frame
        )
    }

    private static func runStatusSubmenuPreviewScenario(context: AutomationContext) throws -> ScenarioResult {
        try press(identifier: "openStatusFolderPopupButton", in: context.appElement)

        let rootBounds = try waitForRectLabel(identifier: "rootPopupFrameLabel", in: context.appElement)
        let submenuBounds = try waitForRectLabel(identifier: "submenuPopupFrameLabel", in: context.appElement)

        // Submenu must be to the left of the root popup.
        if submenuBounds.frame.maxX > rootBounds.frame.minX + 1 {
            throw SmokeFailure(description: "status-submenu-preview: submenu (maxX=\(submenuBounds.frame.maxX)) is not to the left of root popup (minX=\(rootBounds.frame.minX))")
        }

        let submenuItem = try waitForRectLabel(identifier: "selectedSubmenuRowFrameLabel", in: context.appElement)
        moveMouse(to: convertToScreen(rect: submenuItem.frame, in: context.appElement).center)

        let previewFrame = try waitForRectLabel(identifier: "previewFrameLabel", in: context.appElement)

        // Preview must be to the left of the submenu.
        try assertLeftPreview(
            previewFrame: previewFrame.frame,
            menuBounds: submenuBounds.frame,
            referenceFrame: submenuItem.frame,
            scenario: "status-submenu-preview"
        )

        let allMenuBounds = rootBounds.frame.union(submenuBounds.frame)
        return ScenarioResult(
            name: "status-submenu-preview",
            previewFrame: previewFrame.frame,
            referenceFrame: submenuItem.frame,
            allMenuBounds: allMenuBounds
        )
    }

    private static func runKeyboardPreviewScenario(context: AutomationContext) throws -> ScenarioResult {
        try press(identifier: "openPopupButton", in: context.appElement)
        _ = try waitForRectLabel(identifier: "rootPopupFrameLabel", in: context.appElement)

        sendKey(keyCode: 125)

        let highlightText = try waitForLabel(identifier: "highlightCountLabel", in: context.appElement) { value in
            value.hasSuffix(": 1") || value.hasSuffix(": 2")
        }
        guard highlightText.contains("Highlight callback count:") else {
            throw SmokeFailure(description: "Keyboard scenario never highlighted a menu item")
        }

        let highlightedItem = try waitForRectLabel(identifier: "selectedRootRowFrameLabel", in: context.appElement)
        let previewFrame = try waitForRectLabel(identifier: "previewFrameLabel", in: context.appElement)
        let menuBounds = try waitForRectLabel(identifier: "rootPopupFrameLabel", in: context.appElement)

        // Hotkey popups on the left of the canvas open previews to the right of the root menu.
        try assertRightPreview(
            previewFrame: previewFrame.frame,
            menuBounds: menuBounds.frame,
            referenceFrame: highlightedItem.frame,
            scenario: "keyboard-preview"
        )

        return ScenarioResult(
            name: "keyboard-preview",
            previewFrame: previewFrame.frame,
            referenceFrame: highlightedItem.frame,
            allMenuBounds: menuBounds.frame
        )
    }

    private static func runSubmenuPreviewScenario(context: AutomationContext) throws -> ScenarioResult {
        try press(identifier: "openFolderPopupButton", in: context.appElement)
        // openFolderPopup already opens the first submenu programmatically; no need to hover the root row.

        let submenuBounds = try waitForRectLabel(identifier: "submenuPopupFrameLabel", in: context.appElement)
        let submenuItem = try waitForRectLabel(identifier: "selectedSubmenuRowFrameLabel", in: context.appElement)
        moveMouse(to: convertToScreen(rect: submenuItem.frame, in: context.appElement).center)

        let previewFrame = try waitForRectLabel(identifier: "previewFrameLabel", in: context.appElement)
        let rootBounds = try waitForRectLabel(identifier: "rootPopupFrameLabel", in: context.appElement)
        let menuBounds = rootBounds.frame.union(submenuBounds.frame)

        // Hotkey submenus open to the right; the preview must sit to the right of that submenu.
        try assertRightPreview(
            previewFrame: previewFrame.frame,
            menuBounds: submenuBounds.frame,
            referenceFrame: submenuItem.frame,
            scenario: "submenu-preview"
        )

        return ScenarioResult(
            name: "submenu-preview",
            previewFrame: previewFrame.frame,
            referenceFrame: submenuItem.frame,
            allMenuBounds: menuBounds
        )
    }

    private static func runScrollPreviewScenario(context: AutomationContext) throws -> ScenarioResult {
        try press(identifier: "openStatusPopupButton", in: context.appElement)
        let row = try waitForRectLabel(identifier: "selectedRootRowFrameLabel", in: context.appElement)
        moveMouse(to: convertToScreen(rect: row.frame, in: context.appElement).center)

        let previewFrame = try waitForRectLabel(identifier: "previewFrameLabel", in: context.appElement)
        let previewCenter = convertToScreen(rect: previewFrame.frame, in: context.appElement).center

        moveMouse(to: previewCenter)
        sendScroll(deltaY: -80, at: previewCenter)

        let updatedPreviewFrame = try waitForRectLabel(identifier: "previewFrameLabel", in: context.appElement)

        return ScenarioResult(
            name: "scroll-preview",
            previewFrame: updatedPreviewFrame.frame,
            referenceFrame: row.frame,
            allMenuBounds: previewFrame.frame
        )
    }

    private static func press(identifier: String, in root: AXUIElement) throws {
        guard let element = findElement(in: root, where: { element in
            stringAttribute(kAXIdentifierAttribute, of: element) == identifier
        }) else {
            throw SmokeFailure(description: "Could not find element with identifier \(identifier)")
        }

        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw SmokeFailure(description: "AXPress failed for \(identifier) with error \(result.rawValue)")
        }
    }

    private static func waitForRectLabel(identifier: String, in root: AXUIElement) throws -> (text: String, frame: CGRect) {
        if identifier == "previewFrameLabel" {
            // The harness exposes a fallback layout before the delayed preview
            // exists. A nonempty rectangle alone does not mean it was shown.
            _ = try waitForLabel(identifier: "previewCountLabel", in: root) { value in
                guard let count = value.split(separator: ":").last else { return false }
                return (Int(count.trimmingCharacters(in: .whitespaces)) ?? 0) > 0
            }
        }
        var matchedText: String?
        var matchedFrame: CGRect?
        guard spinWait(timeout: 8, condition: {
            guard let element = findElement(in: root, where: { element in
                stringAttribute(kAXIdentifierAttribute, of: element) == identifier
            }),
            let value = bestStringValue(of: element),
            let rect = parseRect(fromLabel: value),
            !rect.isEmpty
            else {
                return false
            }

            matchedText = value
            matchedFrame = rect
            return true
        }) else {
            throw SmokeFailure(description: "Timed out waiting for rect label \(identifier)")
        }

        return (matchedText!, matchedFrame!)
    }

    private static func waitForLabel(
        identifier: String,
        in root: AXUIElement,
        timeout: TimeInterval = 5,
        predicate: (String) -> Bool
    ) throws -> String {
        var matched: String?
        guard spinWait(timeout: timeout, condition: {
            guard let element = findElement(in: root, where: { element in
                stringAttribute(kAXIdentifierAttribute, of: element) == identifier
            }),
            let value = bestStringValue(of: element)
            else {
                return false
            }

            if predicate(value) {
                matched = value
                return true
            }
            return false
        }) else {
            throw SmokeFailure(description: "Timed out waiting for label \(identifier)")
        }

        return matched!
    }
    private static func assertLeftPreview(previewFrame: CGRect, menuBounds: CGRect, referenceFrame: CGRect, scenario: String) throws {
        if previewFrame.maxX > menuBounds.minX {
            throw SmokeFailure(description: "\(scenario): preview (maxX=\(previewFrame.maxX)) is not to the left of menu (minX=\(menuBounds.minX))")
        }

        let gap = menuBounds.minX - previewFrame.maxX
        if gap > 16 {
            throw SmokeFailure(description: "\(scenario): preview (maxX=\(previewFrame.maxX)) is too far from menu (minX=\(menuBounds.minX)), gap=\(gap)px > 16px")
        }

        try assertPreviewVerticallyAligned(
            previewFrame: previewFrame,
            referenceFrame: referenceFrame,
            scenario: scenario
        )
    }

    private static func assertRightPreview(previewFrame: CGRect, menuBounds: CGRect, referenceFrame: CGRect, scenario: String) throws {
        if previewFrame.minX < menuBounds.maxX {
            throw SmokeFailure(description: "\(scenario): preview (minX=\(previewFrame.minX)) is not to the right of menu (maxX=\(menuBounds.maxX))")
        }

        let gap = previewFrame.minX - menuBounds.maxX
        if gap > 16 {
            throw SmokeFailure(description: "\(scenario): preview (minX=\(previewFrame.minX)) is too far from menu (maxX=\(menuBounds.maxX)), gap=\(gap)px > 16px")
        }

        try assertPreviewVerticallyAligned(
            previewFrame: previewFrame,
            referenceFrame: referenceFrame,
            scenario: scenario
        )
    }

    private static func assertPreviewVerticallyAligned(previewFrame: CGRect, referenceFrame: CGRect, scenario: String) throws {
        let vertOffset = abs(previewFrame.midY - referenceFrame.midY)
        if vertOffset > 36 {
            throw SmokeFailure(description: "\(scenario): preview (midY=\(previewFrame.midY)) is not vertically aligned with item row (midY=\(referenceFrame.midY)), offset=\(vertOffset)px > 36px")
        }
    }

    private static func moveMouse(to point: CGPoint) {
        let location = CGPoint(x: point.x, y: point.y)
        CGWarpMouseCursorPosition(location)
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
        usleep(250_000)
    }

    private static func sendKey(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        usleep(300_000)
    }

    private static func sendScroll(deltaY: Int32, at location: CGPoint) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        )
        event?.location = location
        event?.post(tap: .cghidEventTap)
        usleep(150_000)
    }
}

private struct AutomationContext {
    let bundleIdentifier: String
    let process: Process
    let appElement: AXUIElement
    let systemWideElement: AXUIElement

    func terminate() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            app.forceTerminate()
        }
        if process.isRunning {
            process.terminate()
        }
    }
}

private func spinWait(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    }
    return condition()
}

private func findElement(in root: AXUIElement, where predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    var visited = Set<CFHashCode>()
    return findElement(in: root, visited: &visited, where: predicate)
}

private func findElement(in root: AXUIElement, visited: inout Set<CFHashCode>, where predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    let key = CFHash(root)
    guard !visited.contains(key) else { return nil }
    visited.insert(key)

    if predicate(root) {
        return root
    }

    for child in childElements(of: root) {
        if let match = findElement(in: child, visited: &visited, where: predicate) {
            return match
        }
    }

    return nil
}

private func findAllElements(in root: AXUIElement, where predicate: (AXUIElement) -> Bool) -> [AXUIElement] {
    var visited = Set<CFHashCode>()
    var results: [AXUIElement] = []
    findAllElements(in: root, visited: &visited, where: predicate, results: &results)
    return results
}

private func findAllElements(
    in root: AXUIElement,
    visited: inout Set<CFHashCode>,
    where predicate: (AXUIElement) -> Bool,
    results: inout [AXUIElement]
) {
    let key = CFHash(root)
    guard !visited.contains(key) else { return }
    visited.insert(key)

    if predicate(root) {
        results.append(root)
    }

    for child in childElements(of: root) {
        findAllElements(in: child, visited: &visited, where: predicate, results: &results)
    }
}

private func childElements(of element: AXUIElement) -> [AXUIElement] {
    let attributes = [
        kAXChildrenAttribute,
        kAXWindowsAttribute,
        kAXMenuBarAttribute,
        kAXContentsAttribute,
        kAXVisibleChildrenAttribute,
    ]

    var children: [AXUIElement] = []
    for attribute in attributes {
        if let value = attributeValue(attribute, of: element) {
            let typeID = CFGetTypeID(value)
            if typeID == AXUIElementGetTypeID() {
                children.append(unsafeBitCast(value, to: AXUIElement.self))
            } else if typeID == CFArrayGetTypeID() {
                let values = unsafeBitCast(value, to: CFArray.self) as [AnyObject]
                for child in values where CFGetTypeID(child) == AXUIElementGetTypeID() {
                    children.append(unsafeBitCast(child, to: AXUIElement.self))
                }
            }
        }
    }
    return children
}

private func attributeValue(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else { return nil }
    return value
}

private func role(of element: AXUIElement) -> String? {
    stringAttribute(kAXRoleAttribute, of: element)
}

private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
    if let value = attributeValue(attribute, of: element) as? String {
        return value
    }
    if let value = attributeValue(attribute, of: element) as? NSAttributedString {
        return value.string
    }
    return nil
}

private func bestStringValue(of element: AXUIElement) -> String? {
    stringAttribute(kAXValueAttribute, of: element)
        ?? stringAttribute(kAXDescriptionAttribute, of: element)
        ?? stringAttribute(kAXTitleAttribute, of: element)
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attributeValue(kAXPositionAttribute, of: element),
          let sizeValue = attributeValue(kAXSizeAttribute, of: element)
    else {
        return nil
    }

    let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
    let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)

    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetType(positionAXValue) == .cgPoint,
          AXValueGetValue(positionAXValue, .cgPoint, &point),
          AXValueGetType(sizeAXValue) == .cgSize,
          AXValueGetValue(sizeAXValue, .cgSize, &size)
    else {
        return nil
    }

    return CGRect(origin: point, size: size)
}

private func convertToScreen(rect: CGRect, in appElement: AXUIElement) -> CGRect {
    guard let window = findElement(in: appElement, where: { element in
        stringAttribute(kAXTitleAttribute, of: element) == "Paste Integration"
    }), let windowFrame = frame(of: window) else {
        return rect
    }

    return rect.offsetBy(dx: windowFrame.minX, dy: windowFrame.minY)
}

private func parseRect(fromLabel label: String) -> CGRect? {
    guard let range = label.range(of: "\\{\\{[^}]+\\}, \\{[^}]+\\}\\}", options: .regularExpression) else {
        return nil
    }
    return NSRectFromString(String(label[range]))
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private func ensureAutomationAccessibility() -> Bool {
    if AXIsProcessTrusted() {
        return true
    }

    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    return false
}

do {
    try PreviewAXSmokeRunner.run()
} catch {
    fputs("AX smoke failed: \(error)\n", stderr)
    exit(1)
}
