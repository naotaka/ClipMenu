import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// A single row in the clipboard history menu.
///
/// Rendering rules are taken from `legacy/Source/MenuController.m
/// -_makeMenuItemForClip:withCount:andListNumber:`.
struct ClipMenuItem: View {
    private static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "ClipMenuItem")

    let entry: ClipEntry
    /// Numbering prefix (already computed by ClipMenuView).
    let listNumber: Int

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.clipsService) private var clipsService
    @Environment(\.actionService) private var actionService

    var body: some View {
        Button(action: select) {
            itemLabel
        }
        .help(tooltip)
        .modifier(NumericShortcut(number: listNumber % 10,
                                  enabled: settings.numericKeyEquivalents))
    }

    // MARK: - Label

    @ViewBuilder
    private var itemLabel: some View {
        let thumb = settings.showImageInMenu ? thumbnail : nil

        HStack(spacing: 4) {
            // Type icon
            if thumb == nil, settings.showIconInMenu, let icon = typeIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: CGFloat(settings.menuIconSize),
                           height: CGFloat(settings.menuIconSize))
            }

            // Image thumbnail
            if let thumb {
                Image(nsImage: thumb)
            }

            // Title text
            Text(titleText)
                .font(itemFont)

            // Type label badge
            if settings.showLabelsInMenu, let label = primaryTypeName {
                Text("[\(label)]")
                    .foregroundStyle(.secondary)
                    .font(itemFont)
            }
        }
    }

    // MARK: - Title

    private var titleText: String {
        var t = trimmedTitle
        if settings.numberedMenuItems {
            t = "\(listNumber). \(t)"
        }
        return t
    }

    /// Replicates `trimTitle()` from `legacy/Source/MenuController.m`.
    private var trimmedTitle: String {
        let source = entry.stringValue
            ?? entry.filenames?.first
            ?? entry.urlStrings?.first
            ?? ""
        let stripped = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine: String
        if let nl = stripped.firstIndex(of: "\n") {
            firstLine = String(stripped[..<nl])
        } else {
            firstLine = stripped
        }
        let maxLen = settings.maxMenuItemTitleLength
        if firstLine.count > maxLen {
            return String(firstLine.prefix(max(maxLen - 3, 0))) + "..."
        }
        if !firstLine.isEmpty {
            return firstLine
        }
        if entry.imageData != nil {
            return "(Image)"
        }
        return "(binary)"
    }

    // MARK: - Visual properties

    private var thumbnail: NSImage? {
        guard let data = entry.imageData else {
            if titleText.contains("(Image)") {
                Self.log.debug("No imageData available for clip labeled as image")
            }
            return nil
        }
        guard let img = decodedImage(from: data) else {
            Self.log.debug("Failed to decode thumbnail image data bytes=\(data.count, privacy: .public)")
            return nil
        }
        Self.log.debug("Decoded thumbnail image size=\(Int(img.size.width), privacy: .public)x\(Int(img.size.height), privacy: .public) bytes=\(data.count, privacy: .public)")
        return scaledImage(img,
                           to: NSSize(width: CGFloat(settings.thumbnailWidth),
                                      height: CGFloat(settings.thumbnailHeight)))
    }

    private var typeIcon: NSImage? {
        // Use NSWorkspace to resolve a file-type icon for the primary pasteboard type.
        let ext = iconFileExtension(for: entry.types.first ?? "")
        guard !ext.isEmpty else { return nil }
        let contentType = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: contentType)
        return scaledImage(icon, to: NSSize(width: CGFloat(settings.menuIconSize),
                                             height: CGFloat(settings.menuIconSize)))
    }

    /// Maps a pasteboard type string to the file-extension hint used when
    /// asking NSWorkspace for an icon. Mirrors the per-type prefs in settings.
    private func iconFileExtension(for type: String) -> String {
        switch type {
        case "NSStringPboardType", "public.utf8-plain-text":
            return settings.menuIconOfFileTypeTagForString == 0
                ? settings.menuIconOfFileTypeForString
                : hfsToExt(settings.menuIconOfFileTypeForString)
        case "NeXT Rich Text Format v1.0 pasteboard type", "public.rtf":
            return settings.menuIconOfFileTypeForRTF
        case "NeXT RTFD pasteboard type":
            return settings.menuIconOfFileTypeForRTFD
        case "Apple PDF pasteboard type", "com.adobe.pdf":
            return settings.menuIconOfFileTypeForPDF
        case "NSFilenamesPboardType", "public.file-url":
            return settings.menuIconOfFileTypeForFilenames
        case "Apple URL pasteboard type", "public.url":
            return settings.menuIconOfFileTypeForURL
        case "NeXT TIFF v4.0 pasteboard type", "public.tiff":
            return settings.menuIconOfFileTypeForTIFF
        default:
            return ""
        }
    }

    private func hfsToExt(_ hfs: String) -> String { hfs.lowercased() }

    private var primaryTypeName: String? {
        let map: [String: String] = [
            "NSStringPboardType": "String",
            "public.utf8-plain-text": "String",
            "NeXT Rich Text Format v1.0 pasteboard type": "RTF",
            "NeXT RTFD pasteboard type": "RTFD",
            "Apple PDF pasteboard type": "PDF",
            "NSFilenamesPboardType": "Filenames",
            "Apple URL pasteboard type": "URL",
            "NeXT TIFF v4.0 pasteboard type": "TIFF",
            "Apple PICT pasteboard type": "PICT",
        ]
        return entry.types.compactMap { map[$0] }.first
    }

    private var tooltip: String {
        guard settings.showTooltipsInMenu else { return "" }
        let text = entry.stringValue
            ?? entry.filenames?.joined(separator: "\n")
            ?? ""
        return String(text.prefix(settings.maxTooltipLength))
    }

    private var itemFont: Font {
        guard settings.changeFontSize else { return .body }
        let size: CGFloat = settings.fontSizeMode == 0
            ? CGFloat(settings.menuIconSize)
            : CGFloat(settings.selectedFontSize)
        return .system(size: size)
    }

    // MARK: - Action

    private func select() {
        let flags = NSEvent.modifierFlags.intersection([.control, .shift, .option, .command])

        guard settings.enableAction else {
            Task { await clipsService.select(entry) }
            return
        }

        if let behavior = behaviorForFlags(flags), !behavior.isEmpty {
            if behavior == "popUpActionMenu" {
                showActionMenu()
                return
            }

            if let configuredNode = configuredActionNode(from: behavior) {
                Task { await actionService.perform(action: configuredNode, on: entry, executionContext: .pasteContext) }
                return
            }
        }

        Task { await clipsService.select(entry) }
    }

    private func behaviorForFlags(_ flags: NSEvent.ModifierFlags) -> String? {
        switch flags {
        case .control:
            return settings.controlClickBehavior
        case .shift:
            return settings.shiftClickBehavior
        case .option:
            return settings.optionClickBehavior
        case .command:
            return settings.commandClickBehavior
        default:
            return nil
        }
    }

    private func showActionMenu() {
        Task {
            let roots = await actionService.rootActions()
            let enabledRoots = roots.filter(\.isEnabled)

            if settings.invokeActionImmediately,
               enabledRoots.count == 1,
               let only = enabledRoots.first,
               only.isLeaf {
                await actionService.perform(action: only, on: entry, executionContext: .pasteContext)
                return
            }

            await MainActor.run {
                let menu = ActionMenuBuilder.makeMenu(from: enabledRoots, target: entry, service: actionService)
                let event = NSApp.currentEvent
                if let view = event?.window?.contentView {
                    let pointInWindow = event?.locationInWindow ?? .zero
                    let pointInView = view.convert(pointInWindow, from: nil)
                    menu.popUp(positioning: nil, at: pointInView, in: view)
                } else {
                    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                }
            }
        }
    }

    private func configuredActionNode(from rawBehavior: String) -> ActionNode? {
        guard let data = rawBehavior.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }

        let type = (dict["type"] as? String) ?? ""
        let node = ActionNode(title: (dict["name"] as? String) ?? "Configured Action", isLeaf: true)

        if type == "javaScript" || type == "js" {
            node.actionType = "javaScript"
            node.scriptPath = dict["path"] as? String
            node.scriptContent = dict["content"] as? String
            return node
        }

        if type == "builtin" {
            node.actionType = "builtin"
            node.actionName = dict["name"] as? String
            return node
        }

        return nil
    }

    // MARK: - Helpers

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
            return image
        }

        if let rep = NSBitmapImageRep(data: data) {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            return image
        }

        return NSImage(data: data)
    }
}

private struct NumericShortcut: ViewModifier {
    let number: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, let char = Character(String(number)).asciiDigit {
            content.keyboardShortcut(KeyEquivalent(char), modifiers: [])
        } else {
            content
        }
    }
}

private extension Character {
    var asciiDigit: Character? {
        guard self >= "0", self <= "9" else { return nil }
        return self
    }
}

// MARK: - Preview

#Preview("String clip") {
    let entry = ClipEntry()
    entry.stringValue = "Hello, world! This is a sample clipboard entry."
    entry.types = ["NSStringPboardType"]
    return ClipMenuItem(entry: entry, listNumber: 1)
        .environment(ClipMenuSettings())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .padding()
}

#Preview("Binary clip") {
    let entry = ClipEntry()
    entry.types = ["NeXT TIFF v4.0 pasteboard type"]
    return ClipMenuItem(entry: entry, listNumber: 2)
        .environment(ClipMenuSettings())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .padding()
}
