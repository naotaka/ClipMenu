import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// General tab in the Preferences window.
///
/// Covers: login item, paste command, reorder, history size,
/// storage disclosure, status item, store types, app exclusions.
/// Reference: `legacy/Source/PrefsWindowController.{h,m}` General tab.
struct GeneralPrefsView: View {

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.loginItemService) private var loginItem

    var body: some View {
        @Bindable var s = settings
        Form {
            // MARK: Startup
            Section("Startup") {
                Toggle("Launch \(AppDistribution.displayName) at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { val in
                        settings.launchAtLogin = val
                        try? loginItem.setEnabled(val)
                    }
                ))
            }

            if AppDistribution.usesAccessibility {
                Section("Automatic Paste") {
                    AutomaticPasteSection()
                }
            }

            // MARK: Clipboard Behaviour
            Section("Clipboard") {
                if AppDistribution.usesAccessibility {
                    Toggle("Paste automatically after selection", isOn: $s.autoPasteAfterSelection)
                } else {
                    Text("Choose a clip by clicking it with your mouse, or with the arrow keys and enter. This copies it to your clipboard, so you can then paste it with command V.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Move used clip to top of history", isOn: $s.reorderClipsAfterPasting)
                LabeledContent("Maximum history size") {
                    TextField("", value: $s.maxHistorySize, format: .number)
                        .frame(width: 60)
                }
                Text("History is saved automatically on this Mac. Saved history and snippets are encrypted on this Mac, and the keys stay in the Keychain. Clear History removes saved clips, empties the clipboard, and retires the history key. Snippets are kept. Copies in backups or other apps cannot be removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Store Types
            Section("Store Types") {
                StoreTypesGrid(settings: settings)
            }

            // MARK: Excluded Apps
            Section("Excluded Applications") {
                ExcludeAppsEditor(settings: settings)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AutomaticPasteSection: View {
    @Environment(ClipMenuSettings.self) private var settings
    @State private var isTrusted = PasteService.accessibilityStatus().isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isTrusted {
                Text("Automatic paste is on. Accessibility is used only to paste the clip you choose.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Without Accessibility permission, each clip is copied and you paste it yourself. Permission is used only for that paste.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Automatic Paste") {
                    _ = AutomaticPastePrompt.allowsPaste(settings: settings, ignoreDecline: true)
                    isTrusted = PasteService.accessibilityStatus().isTrusted
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isTrusted = PasteService.accessibilityStatus().isTrusted
    }
}

// MARK: - Store Types sub-view

private struct StoreTypesGrid: View {

    let settings: ClipMenuSettings
    private let types = ["String", "RTF", "RTFD", "PDF", "Filenames", "URL", "TIFF", "PICT"]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading) {
            ForEach(types, id: \.self) { typeName in
                Toggle(typeName, isOn: Binding(
                    get: { settings.storeTypes[typeName] ?? true },
                    set: { val in
                        var dict = settings.storeTypes
                        dict[typeName] = val
                        settings.storeTypes = dict
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Excluded apps sub-view

private struct ExcludeAppsEditor: View {

    let settings: ClipMenuSettings
    @State private var selection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selection) {
                ForEach(settings.excludeApps, id: \.self) { app in
                    let bundleIdentifier = app["bundleIdentifier"] ?? ""
                    Text(app["name"] ?? bundleIdentifier)
                        .tag(bundleIdentifier)
                }
            }
            .frame(minHeight: 80)

            HStack {
                Button("Add…") { chooseApplication() }
                Button("Remove") { removeSelected() }
                    .disabled(selection == nil)
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Exclude an Application"
        panel.message = "Clipboard history will skip copies while this application is active."
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier,
              !settings.excludeApps.contains(where: { $0["bundleIdentifier"] == id })
        else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        settings.excludeApps.append(["bundleIdentifier": id, "name": name])
    }

    private func removeSelected() {
        guard let sel = selection else { return }
        settings.excludeApps.removeAll { $0["bundleIdentifier"] == sel }
        selection = nil
    }
}

// MARK: - Preview

#Preview {
    GeneralPrefsView()
        .environment(ClipMenuSettings())
        .environment(\.loginItemService, LoginItemService())
        .frame(width: 520)
}
