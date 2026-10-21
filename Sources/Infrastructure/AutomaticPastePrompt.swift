import AppKit

/// Explains automatic paste before macOS asks for Accessibility.
///
/// Declining keeps the clip on the clipboard and stays quiet until Preferences
/// asks again. Allowing opens the system prompt, which is the only place the
/// permission is actually granted.
@MainActor
enum AutomaticPastePrompt {
    /// Returns true when clip'M may synthesize Command-V.
    @discardableResult
    static func allowsPaste(settings: ClipMenuSettings, ignoreDecline: Bool = false) -> Bool {
        if PasteService.accessibilityStatus().isTrusted { return true }
        if settings.declinedAutomaticPaste && !ignoreDecline { return false }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let alert = NSAlert()
        alert.messageText = "Paste in one step?"
        alert.accessoryView = pasteExplanation()
        alert.addButton(withTitle: "Allow Automatic Paste")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            return PasteService.requestAccessibilityPermissionIfNeeded()
        }
        settings.declinedAutomaticPaste = true
        return false
    }

    /// The system alert cannot color one phrase, so the explanation is drawn here.
    private static func pasteExplanation() -> NSView {
        let name = AppDistribution.displayName
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let bodyColor = NSColor.labelColor
        let emphasisFont = NSFont.systemFont(ofSize: 14)
        let emphasisColor = NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(srgbRed: 0.62, green: 0.80, blue: 1.0, alpha: 1)
            }
            return NSColor(srgbRed: 0.10, green: 0.32, blue: 0.78, alpha: 1)
        })

        let text = NSMutableAttributedString()
        func append(_ string: String, emphasized: Bool = false) {
            text.append(NSAttributedString(string: string, attributes: [
                .font: emphasized ? emphasisFont : bodyFont,
                .foregroundColor: emphasized ? emphasisColor : bodyColor,
                .paragraphStyle: paragraph,
            ]))
        }
        append("\(name) can paste the clip you choose in one step when you allow Accessibility.\n\n")
        append("macOS will then say \(name) would like to control this computer. This 'controlling' is ")
        append("ONLY FOR PASTING", emphasized: true)
        append(", nothing else.\n\n")
        append("If you skip this, \(name) still keeps track of what you copy. Choosing a clip copies it, and you paste it yourself. That takes two steps. Allow Automatic Paste and you skip the second one.")

        let field = NSTextField(wrappingLabelWithString: " ")
        field.attributedStringValue = text
        field.preferredMaxLayoutWidth = 360
        field.maximumNumberOfLines = 0
        let size = field.sizeThatFits(NSSize(width: 360, height: 2_000))
        field.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: ceil(size.height)))
        return field
    }
}
