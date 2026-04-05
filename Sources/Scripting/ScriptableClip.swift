import JavaScriptCore
import AppKit

/// The JavaScript-visible bridge object that exposes clipboard content to
/// action scripts.
///
/// Replicates the JSExport protocol surface from
/// `legacy/Source/ScriptableClip.{h,m}`.
@objc protocol ScriptableClipExports: JSExport {
    var text: String? { get }
    func setStringAttributes(_ attrs: [String: Any])
    func addStringAttributes(_ attrs: [String: Any])
}

@objc final class ScriptableClip: NSObject, ScriptableClipExports {

    private let entry: ClipEntry

    init(entry: ClipEntry) {
        self.entry = entry
    }

    var text: String? { entry.stringValue }

    func setStringAttributes(_ attrs: [String: Any]) {
        applyAttributes(attrs, mode: .set)
    }

    func addStringAttributes(_ attrs: [String: Any]) {
        applyAttributes(attrs, mode: .add)
    }

    // MARK: - Private

    private enum AttributeMode { case set, add }

    private func applyAttributes(_ attrs: [String: Any], mode: AttributeMode) {
        guard entry.stringValue != nil, let rtfData = entry.rtfData else { return }

        let attrString: NSMutableAttributedString
        if entry.isRTFD {
            attrString = NSMutableAttributedString(rtfd: rtfData, documentAttributes: nil)
                ?? NSMutableAttributedString()
        } else {
            attrString = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil)
                ?? NSMutableAttributedString()
        }

        let range = NSRange(location: 0, length: attrString.length)
        var nsAttrs: [NSAttributedString.Key: Any] = [:]

        if let colorDict = attrs["color"] as? [String: Any] {
            if let fg = colorDict["foreground"] as? String,
               let color = NSColor(cssName: fg) {
                nsAttrs[.foregroundColor] = color
            }
            if let bg = colorDict["background"] as? String,
               let color = NSColor(cssName: bg) {
                nsAttrs[.backgroundColor] = color
            }
        }

        if let fontDict = attrs["font"] as? [String: Any],
           let name = fontDict["name"] as? String,
           let size = fontDict["size"] as? CGFloat,
           let font = NSFont(name: name, size: size) {
            nsAttrs[.font] = font
        }

        if let ulDict = attrs["underline"] as? [String: Any] {
            var mask: Int = 0
            mask |= underlineStyle(from: ulDict["style"] as? String)
            mask |= underlinePattern(from: ulDict["pattern"] as? String)
            if (ulDict["byWord"] as? Bool) == true { mask |= NSUnderlineStyle.byWord.rawValue }
            nsAttrs[.underlineStyle] = mask
        }

        guard !nsAttrs.isEmpty else { return }
        attrString.beginEditing()
        switch mode {
        case .set: attrString.setAttributes(nsAttrs, range: range)
        case .add: attrString.addAttributes(nsAttrs, range: range)
        }
        attrString.fixAttributes(in: range)
        attrString.endEditing()

        if entry.isRTFD {
            entry.rtfData = attrString.rtfd(from: range, documentAttributes: [:])
        } else {
            entry.rtfData = attrString.rtf(from: range, documentAttributes: [:])
        }
    }

    private func underlineStyle(from name: String?) -> Int {
        switch name?.lowercased() {
        case "single": return NSUnderlineStyle.single.rawValue
        case "thick":  return NSUnderlineStyle.thick.rawValue
        case "double": return NSUnderlineStyle.double.rawValue
        default:       return 0
        }
    }

    private func underlinePattern(from name: String?) -> Int {
        switch name?.lowercased() {
        case "dot":        return NSUnderlineStyle.patternDot.rawValue
        case "dash":       return NSUnderlineStyle.patternDash.rawValue
        case "dashdot":    return NSUnderlineStyle.patternDashDot.rawValue
        case "dashdotdot": return NSUnderlineStyle.patternDashDotDot.rawValue
        default:           return 0
        }
    }
}

// MARK: - NSColor CSS name extension

private extension NSColor {
    convenience init?(cssName: String) {
        // Hex color support: #RGB, #RRGGBB
        if cssName.hasPrefix("#") {
            let hex = cssName.dropFirst()
            var value: UInt64 = 0
            guard Scanner(string: String(hex)).scanHexInt64(&value) else { return nil }
            let length = hex.count
            if length == 3 {
                let r = CGFloat((value >> 8) & 0xF) / 15.0
                let g = CGFloat((value >> 4) & 0xF) / 15.0
                let b = CGFloat(value & 0xF) / 15.0
                self.init(red: r, green: g, blue: b, alpha: 1)
            } else if length == 6 {
                let r = CGFloat((value >> 16) & 0xFF) / 255.0
                let g = CGFloat((value >> 8) & 0xFF) / 255.0
                let b = CGFloat(value & 0xFF) / 255.0
                self.init(red: r, green: g, blue: b, alpha: 1)
            } else {
                return nil
            }
            return
        }
        // Named CSS colors (subset used by legacy JavaScriptSupport)
        let named: [String: (CGFloat, CGFloat, CGFloat)] = [
            "black":   (0, 0, 0),       "white":   (1, 1, 1),
            "red":     (1, 0, 0),       "green":   (0, 0.502, 0),
            "blue":    (0, 0, 1),       "yellow":  (1, 1, 0),
            "cyan":    (0, 1, 1),       "magenta": (1, 0, 1),
            "orange":  (1, 0.647, 0),   "purple":  (0.502, 0, 0.502),
            "brown":   (0.647, 0.165, 0.165),
            "gray":    (0.502, 0.502, 0.502),
            "grey":    (0.502, 0.502, 0.502),
            "silver":  (0.753, 0.753, 0.753),
        ]
        if let rgb = named[cssName.lowercased()] {
            self.init(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        } else {
            return nil
        }
    }
}
