import SwiftUI
import AppKit

/// General tab in the Preferences window.
///
/// Covers: login item, paste command, reorder, history size,
/// save-on-quit, status item, store types, app exclusions.
/// Reference: `legacy/Source/PrefsWindowController.{h,m}` General tab.
struct GeneralPrefsView: View {

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.loginItemService) private var loginItem

    var body: some View {
        @Bindable var s = settings
        Form {
            // MARK: Startup
            Section("Startup") {
                Toggle("Launch ClipMenu at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { val in
                        settings.launchAtLogin = val
                        try? loginItem.setEnabled(val)
                    }
                ))
            }

            // MARK: Clipboard Behaviour
            Section("Clipboard") {
                Toggle("Paste automatically after selection", isOn: $s.autoPasteAfterSelection)
                Toggle("Move used clip to top of history", isOn: $s.reorderClipsAfterPasting)
                LabeledContent("Maximum history size") {
                    TextField("", value: $s.maxHistorySize, format: .number)
                        .frame(width: 60)
                }
                Toggle("Save history when quitting", isOn: $s.saveHistoryOnQuit)
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
                    Text(app["name"] ?? app["bundleIdentifier"] ?? "")
                        .tag(app["bundleIdentifier"])
                }
            }
            .frame(minHeight: 80)

            HStack {
                Button("Add") { addFrontmostApp() }
                Button("Remove") { removeSelected() }
                    .disabled(selection == nil)
            }
        }
    }

    private func addFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier,
              let name = app.localizedName,
              !settings.excludeApps.contains(where: { $0["bundleIdentifier"] == id })
        else { return }
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
