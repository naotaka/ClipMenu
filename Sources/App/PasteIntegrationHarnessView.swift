import SwiftUI
import SwiftData

struct PasteIntegrationHarnessView: View {
    private let sampleText = "ClipMenu UI test paste"
    private let alternateSampleText = "ClipMenu UI test preview target"
    private let submenuSampleText = "ClipMenu UI test submenu preview"
    private let runtime = AppRuntime.shared
    private let usesNativeMenu = ProcessInfo.processInfo.environment["CLIPMENU_NATIVE_MENU_TEST"] == "1"

    @Environment(\.modelContext) private var modelContext
    @StateObject private var popupStore = ClipMenuTestPopupStore.shared
    @FocusState private var isFieldFocused: Bool
    @State private var text = ""
    @State private var accessibilityStatus = PasteService.accessibilityStatus()
    @State private var simulatedPasteCount = 0
    @State private var lastSimulatedPaste = ""
    @State private var highlightCount = 0
    @State private var lastHighlightTitle = ""
    @State private var previewShowCount = 0
    @State private var lastPreviewTitle = ""
    @State private var lastPreviewFrame = ""
    @State private var stepStatus = "Idle"

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste Integration Harness")
                        .font(.headline)

                    TextField("Paste target", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFieldFocused)
                        .accessibilityIdentifier("pasteTargetField")

                    Button("Open Popup") {
                        Task { @MainActor in openPopup() }
                    }
                    .accessibilityIdentifier("openPopupButton")

                    Button("Open Status Popup") {
                        Task { @MainActor in openStatusPopup() }
                    }
                    .accessibilityIdentifier("openStatusPopupButton")

                    Button("Open Folder Popup") {
                        Task { @MainActor in openFolderPopup() }
                    }
                    .accessibilityIdentifier("openFolderPopupButton")

                    Button("Open Status Folder Popup") {
                        Task { @MainActor in openStatusFolderPopup() }
                    }
                    .accessibilityIdentifier("openStatusFolderPopupButton")

                    Text(accessibilityTrustText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accessibilityStatus.isTrusted ? .green : .red)
                        .accessibilityIdentifier("accessibilityTrustLabel")
                        .accessibilityLabel(accessibilityTrustText)

                    Text(accessibilityStatus.bundleIdentifier)
                        .font(.caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("bundleIdentifierLabel")
                        .accessibilityLabel(accessibilityStatus.bundleIdentifier)

                    Text(accessibilityStatus.executablePath)
                        .font(.caption2)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .accessibilityIdentifier("executablePathLabel")
                        .accessibilityLabel(accessibilityStatus.executablePath)

                    Text(menuSeedStatusText)
                        .font(.caption)
                        .accessibilityIdentifier("menuSeedStatusLabel")
                        .accessibilityLabel(menuSeedStatusText)

                    Text(stepStatusText)
                        .font(.caption)
                        .accessibilityIdentifier("stepStatusLabel")
                        .accessibilityLabel(stepStatusText)

                    Text(simulatedPasteCountText)
                        .font(.caption)
                        .accessibilityIdentifier("simulatedPasteCountLabel")
                        .accessibilityLabel(simulatedPasteCountText)

                    Text(simulatedPastePayloadText)
                        .font(.caption2)
                        .lineLimit(2)
                        .accessibilityIdentifier("simulatedPastePayloadLabel")
                        .accessibilityLabel(simulatedPastePayloadText)

                    Text(highlightCountText)
                        .font(.caption)
                        .accessibilityIdentifier("highlightCountLabel")
                        .accessibilityLabel(highlightCountText)

                    Text(highlightTitleText)
                        .font(.caption2)
                        .lineLimit(2)
                        .accessibilityIdentifier("highlightTitleLabel")
                        .accessibilityLabel(highlightTitleText)

                    Text(previewCountText)
                        .font(.caption)
                        .accessibilityIdentifier("previewCountLabel")
                        .accessibilityLabel(previewCountText)

                    Text(previewTitleText)
                        .font(.caption2)
                        .lineLimit(2)
                        .accessibilityIdentifier("previewTitleLabel")
                        .accessibilityLabel(previewTitleText)

            Text(previewFrameText)
                .font(.caption2)
                .lineLimit(3)
                .accessibilityIdentifier("previewFrameLabel")
                .accessibilityLabel(previewFrameText)

            Text(rootPopupFrameText)
                .font(.caption2)
                .lineLimit(2)
                .accessibilityIdentifier("rootPopupFrameLabel")
                .accessibilityLabel(rootPopupFrameText)

            Text(selectedRootRowFrameText)
                .font(.caption2)
                .lineLimit(2)
                .accessibilityIdentifier("selectedRootRowFrameLabel")
                .accessibilityLabel(selectedRootRowFrameText)

            Text(submenuPopupFrameText)
                .font(.caption2)
                .lineLimit(2)
                .accessibilityIdentifier("submenuPopupFrameLabel")
                .accessibilityLabel(submenuPopupFrameText)

            Text(selectedSubmenuRowFrameText)
                .font(.caption2)
                .lineLimit(2)
                .accessibilityIdentifier("selectedSubmenuRowFrameLabel")
                .accessibilityLabel(selectedSubmenuRowFrameText)

                    Text(resultText)
                        .accessibilityIdentifier("pasteResultLabel")
                        .accessibilityLabel(resultText)
                }
                .padding(20)

                if popupStore.isVisible {
                    ClipMenuTestPopupOverlay(
                        store: popupStore,
                        geometrySize: geometry.size,
                        onActivate: {
                            NSApp.activate(ignoringOtherApps: true)
                            isFieldFocused = true
                        }
                    )
                }
            }
        }
        .frame(width: 1100, height: 820)
        .onReceive(NotificationCenter.default.publisher(for: PasteService.simulatedPasteNotification)) { notification in
            let pasted = notification.userInfo?["string"] as? String ?? ""
            simulatedPasteCount += 1
            lastSimulatedPaste = pasted
            text = pasted
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipMenuHighlightDidChange)) { notification in
            highlightCount += 1
            lastHighlightTitle = notification.userInfo?["title"] as? String ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipMenuPreviewDidShow)) { notification in
            previewShowCount += 1
            lastPreviewTitle = notification.userInfo?["title"] as? String ?? ""
            lastPreviewFrame = notification.userInfo?["frame"] as? String ?? ""
        }
        .onChange(of: popupStore.previewNode?.id) { _, newValue in
            guard let previewNode = popupStore.previewNode else {
                lastPreviewTitle = ""
                return
            }
            previewShowCount += 1
            lastPreviewTitle = previewNode.title
            lastPreviewFrame = newValue ?? ""
        }
        .onAppear {
            configureRuntimeForPopupTest()
            seedSampleClip()
            if usesNativeMenu {
                Task { await runtime.actionService.start(context: modelContext) }
            }
            refreshAccessibilityStatus()
            NSApp.activate(ignoringOtherApps: true)
            isFieldFocused = true
        }
    }

    @MainActor
    private func openPopup() {
        configureRuntimeForMainPopupTest()
        isFieldFocused = true
        stepStatus = "Showing popup"
        runtime.hotkeyService.presentMainMenuForTesting()
        refreshAccessibilityStatus()
    }

    @MainActor
    private func openStatusPopup() {
        configureRuntimeForMainPopupTest()
        isFieldFocused = true
        stepStatus = "Showing status popup"
        runtime.hotkeyService.presentStatusMenuForTesting()
        stepStatus = "Status popup scheduled"
        refreshAccessibilityStatus()
    }

    @MainActor
    private func openFolderPopup() {
        configureRuntimeForFolderPopupTest()
        isFieldFocused = true
        stepStatus = "Showing folder popup"
        runtime.hotkeyService.presentMainMenuForTesting()
        ClipMenuTestPopupStore.shared.openFirstFolderSubmenu()
        refreshAccessibilityStatus()
    }

    @MainActor
    private func openStatusFolderPopup() {
        configureRuntimeForFolderPopupTest()
        isFieldFocused = true
        stepStatus = "Showing status folder popup"
        runtime.hotkeyService.presentStatusMenuForTesting()
        ClipMenuTestPopupStore.shared.openFirstFolderSubmenu()
        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        accessibilityStatus = PasteService.accessibilityStatus()
    }

    private var accessibilityTrustText: String {
        accessibilityStatus.isTrusted ? "Accessibility: granted" : "Accessibility: missing"
    }

    private var menuSeedStatusText: String {
        "Seeded menu clip: \(sampleText)"
    }

    private var stepStatusText: String {
        "Step status: \(stepStatus)"
    }

    private var simulatedPasteCountText: String {
        "Paste callback count: \(simulatedPasteCount)"
    }

    private var simulatedPastePayloadText: String {
        "Last callback payload: \(lastSimulatedPaste)"
    }

    private var highlightCountText: String {
        "Highlight callback count: \(highlightCount)"
    }

    private var highlightTitleText: String {
        "Last highlight title: \(lastHighlightTitle)"
    }

    private var previewCountText: String {
        "Preview callback count: \(previewShowCount)"
    }

    private var previewTitleText: String {
        "Last preview title: \(lastPreviewTitle)"
    }

    private var previewFrameText: String {
        "Last preview frame: \(currentPreviewFrameString)"
    }

    private var rootPopupFrameText: String {
        "Root popup frame: \(NSStringFromRect(ClipMenuTestPopupLayout.rootPopupFrame(for: popupStore, in: CGSize(width: 1100, height: 820))))"
    }

    private var selectedRootRowFrameText: String {
        "Selected root row frame: \(NSStringFromRect(ClipMenuTestPopupLayout.selectedRowFrame(for: popupStore, level: 0, in: CGSize(width: 1100, height: 820))))"
    }

    private var submenuPopupFrameText: String {
        "Submenu popup frame: \(NSStringFromRect(ClipMenuTestPopupLayout.submenuPopupFrame(for: popupStore, in: CGSize(width: 1100, height: 820))))"
    }

    private var selectedSubmenuRowFrameText: String {
        "Selected submenu row frame: \(NSStringFromRect(ClipMenuTestPopupLayout.selectedRowFrame(for: popupStore, level: 1, in: CGSize(width: 1100, height: 820))))"
    }

    private var currentPreviewFrameString: String {
        NSStringFromRect(ClipMenuTestPopupLayout.previewFrame(for: popupStore, in: CGSize(width: 1100, height: 820)))
    }

    private var resultText: String {
        "Rendered result: \(text)"
    }

    @MainActor
    private func configureRuntimeForPopupTest() {
        configureRuntimeForMainPopupTest()
    }

    @MainActor
    private func configureRuntimeForMainPopupTest() {
        runtime.settings.autoPasteAfterSelection = true
        runtime.settings.enableAction = usesNativeMenu
        if usesNativeMenu {
            runtime.settings.actionModifierKey = 1
            runtime.settings.invokeActionImmediately = false
        }
        runtime.settings.showLabelsInMenu = false
        runtime.settings.showClearHistoryItem = false
        runtime.settings.numberOfItemsInline = 2
        runtime.settings.numberOfItemsInsideFolder = 10
        runtime.settings.numberedMenuItems = false
        runtime.settings.maxMenuItemTitleLength = 200
        runtime.settings.showTooltipsInMenu = true
    }

    @MainActor
    private func configureRuntimeForFolderPopupTest() {
        configureRuntimeForMainPopupTest()
        runtime.settings.numberOfItemsInline = 1
        runtime.settings.numberOfItemsInsideFolder = 1
    }

    @MainActor
    private func seedSampleClip() {
        stepStatus = "Seeding popup clip"

        do {
            let existing = try modelContext.fetch(FetchDescriptor<ClipEntry>())
            if !existing.contains(where: { $0.stringValue == sampleText }) {
                let entry = ClipEntry()
                entry.stringValue = sampleText
                entry.types = [NSPasteboard.PasteboardType.string.rawValue]
                modelContext.insert(entry)
            }

            if !existing.contains(where: { $0.stringValue == alternateSampleText }) {
                let alternate = ClipEntry()
                alternate.stringValue = alternateSampleText
                alternate.types = [NSPasteboard.PasteboardType.string.rawValue]
                alternate.lastUsedAt = Date(timeIntervalSinceNow: -60)
                modelContext.insert(alternate)
            }

            if !existing.contains(where: { $0.stringValue == submenuSampleText }) {
                let submenu = ClipEntry()
                submenu.stringValue = submenuSampleText
                submenu.types = [NSPasteboard.PasteboardType.string.rawValue]
                submenu.lastUsedAt = Date(timeIntervalSinceNow: -120)
                modelContext.insert(submenu)
            }

            try modelContext.save()
            stepStatus = "Popup clip ready"
        } catch {
            stepStatus = "Failed to seed popup clip"
        }
    }
}

private struct ClipMenuTestPopupOverlay: View {
    @ObservedObject var store: ClipMenuTestPopupStore
    let geometrySize: CGSize
    let onActivate: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ClipMenuPopupKeyMonitor(store: store)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)

            popupView(level: 0)
                .position(x: rootOrigin.x + ClipMenuTestPopupLayout.popupWidth / 2, y: rootOrigin.y + popupHeight(for: 0) / 2)

            if !store.nodes(for: 1).isEmpty {
                popupView(level: 1)
                    .position(x: submenuOrigin.x + ClipMenuTestPopupLayout.popupWidth / 2, y: submenuOrigin.y + popupHeight(for: 1) / 2)
            }

            if let previewNode = store.previewNode, store.previewLevel != nil {
                let previewFrame = ClipMenuTestPopupLayout.previewFrame(for: store, in: geometrySize)
                previewView(node: previewNode)
                    .position(x: previewFrame.midX, y: previewFrame.midY)
                    .accessibilityIdentifier("clipPreviewPanel")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: onActivate)
    }

    private func popupView(level: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.nodes(for: level)) { node in
                if node.isSeparator {
                    Divider()
                        .padding(.vertical, 4)
                } else {
                    Button {
                        if node.isFolder {
                            store.openSelectedSubmenu(level: level)
                        } else {
                            store.activationHandler?(node)
                            store.dismiss()
                        }
                    } label: {
                        HStack {
                            Text(node.title)
                                .lineLimit(1)
                            Spacer()
                            if node.isFolder {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: ClipMenuTestPopupLayout.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.isSelected(node, level: level) ? Color.accentColor : Color.clear)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clipTestPopupRow.\(level).\(node.id)")
                    .onHover { hovering in
                        if hovering {
                            store.hover(node: node, level: level)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: ClipMenuTestPopupLayout.popupWidth, height: popupHeight(for: level), alignment: .topLeading)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("clipTestPopupWindow.\(level)")
        .accessibilityLabel(level == 0 ? "Clip Popup" : "Clip Submenu \(level)")
    }

    private func previewView(node: TestPopupNode) -> some View {
        let size = previewSize(for: node)
        let previewText = node.clip?.stringValue ?? node.snippet?.content
        return VStack(alignment: .leading, spacing: 10) {
            Text(node.title)
                .font(.headline)
                .foregroundStyle(.white)

            if let text = previewText {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
        .padding(14)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(.blue.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var rootOrigin: CGPoint {
        ClipMenuTestPopupLayout.rootOrigin(for: store, in: geometrySize)
    }

    private var submenuOrigin: CGPoint {
        ClipMenuTestPopupLayout.submenuPopupFrame(for: store, in: geometrySize).origin
    }

    private func popupHeight(for level: Int) -> CGFloat {
        let count = max(CGFloat(store.nodes(for: level).count), 1)
        return min(max(count * ClipMenuTestPopupLayout.rowHeight + 16, 90), 360)
    }

    private func previewSize(for node: TestPopupNode) -> CGSize {
        let text = node.clip?.stringValue ?? node.snippet?.content ?? node.title
        let width: CGFloat = 280
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width - 28, height: 220),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )
        return CGSize(width: width, height: min(max(rect.height + 64, 110), 260))
    }
}

private struct ClipMenuPopupKeyMonitor: NSViewRepresentable {
    @ObservedObject var store: ClipMenuTestPopupStore

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.onKeyDown = { event in
            switch event.keyCode {
            case 125:
                store.moveSelection(delta: 1, level: 0)
            case 126:
                store.moveSelection(delta: -1, level: 0)
            case 124:
                store.openSelectedSubmenu(level: 0)
            case 123:
                store.closeSubmenu(level: 1)
            case 36, 76:
                let targetLevel = store.nodes(for: 1).isEmpty ? 0 : 1
                store.activateSelected(level: targetLevel)
            case 53:
                store.dismiss()
            default:
                break
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        nsView.window?.makeFirstResponder(nsView)
    }
}

private final class KeyMonitorView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}

@MainActor
private enum ClipMenuTestPopupLayout {
    static let popupWidth: CGFloat = 320
    static let rowHeight: CGFloat = 34
    static let popupSpacing: CGFloat = 16

    static func rootOrigin(for store: ClipMenuTestPopupStore, in size: CGSize) -> CGPoint {
        switch store.source {
        case .hotkey:
            // Leave room for a right-opening submenu plus preview inside the harness canvas.
            return CGPoint(x: 80, y: 170)
        case .status:
            return CGPoint(x: 700, y: 80)
        }
    }

    static func popupHeight(for store: ClipMenuTestPopupStore, level: Int) -> CGFloat {
        let count = max(CGFloat(store.nodes(for: level).count), 1)
        return min(max(count * rowHeight + 16, 90), 360)
    }

    static func rootPopupFrame(for store: ClipMenuTestPopupStore, in size: CGSize) -> CGRect {
        let origin = rootOrigin(for: store, in: size)
        return CGRect(origin: origin, size: CGSize(width: popupWidth, height: popupHeight(for: store, level: 0)))
    }

    static func submenuPopupFrame(for store: ClipMenuTestPopupStore, in size: CGSize) -> CGRect {
        guard !store.nodes(for: 1).isEmpty || firstFolderNode(in: store) != nil else { return .zero }
        let root = rootOrigin(for: store, in: size)
        let submenuX: CGFloat
        switch store.source {
        case .hotkey:
            submenuX = root.x + popupWidth + popupSpacing
        case .status:
            submenuX = root.x - popupSpacing - popupWidth
        }
        let origin = CGPoint(x: submenuX, y: root.y + rowHeight + 8)
        return CGRect(origin: origin, size: CGSize(width: popupWidth, height: popupHeight(for: store, level: 1)))
    }

    static func selectedRowFrame(for store: ClipMenuTestPopupStore, level: Int, in size: CGSize) -> CGRect {
        let index: Int
        if let selectedID = store.selectedNodeID(for: level),
           let selectedIndex = store.nodes(for: level).firstIndex(where: { $0.id == selectedID }) {
            index = selectedIndex
        } else if level == 1, let firstFolder = firstFolderNode(in: store), !firstFolder.children.isEmpty {
            index = 0
        } else {
            return .zero
        }

        let popupFrame = level == 0 ? rootPopupFrame(for: store, in: size) : submenuPopupFrame(for: store, in: size)
        return CGRect(
            x: popupFrame.minX + 8,
            y: popupFrame.minY + 8 + CGFloat(index) * rowHeight,
            width: popupWidth - 16,
            height: rowHeight
        )
    }

    static func previewFrame(for store: ClipMenuTestPopupStore, in size: CGSize) -> CGRect {
        let node: TestPopupNode
        let previewLevel: Int
        if let previewNode = store.previewNode, let storedLevel = store.previewLevel {
            node = previewNode
            previewLevel = storedLevel
        } else {
            return .zero
        }
        let popupFrame = previewLevel == 0
            ? rootPopupFrame(for: store, in: size)
            : submenuPopupFrame(for: store, in: size)
        let previewSize = CGSize(width: 280, height: previewHeight(for: node))
        // Hotkey popups sit on the left of the canvas, so submenus and previews open to the right.
        // Status-bar popups open to the left, matching production.
        let previewX: CGFloat
        switch store.source {
        case .hotkey:
            previewX = popupFrame.maxX + popupSpacing
        case .status:
            previewX = popupFrame.minX - popupSpacing - previewSize.width
        }
        let rowFrame = selectedRowFrame(for: store, level: previewLevel, in: size)
        let previewY = rowFrame.isEmpty ? popupFrame.minY : rowFrame.midY - previewSize.height / 2
        return CGRect(
            x: previewX,
            y: previewY,
            width: previewSize.width,
            height: previewSize.height
        )
    }

    private static func previewHeight(for node: TestPopupNode) -> CGFloat {
        let text = node.clip?.stringValue ?? node.snippet?.content ?? node.title
        let width: CGFloat = 252
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 220),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )
        return min(max(rect.height + 64, 110), 260)
    }

    private static func firstFolderNode(in store: ClipMenuTestPopupStore) -> TestPopupNode? {
        store.nodes(for: 0).first(where: { $0.isFolder && $0.isEnabled })
    }
}
