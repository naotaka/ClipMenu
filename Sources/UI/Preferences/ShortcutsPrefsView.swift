import SwiftUI
import KeyboardShortcuts

/// Shortcuts tab in the Preferences window.
///
/// Displays `KeyboardShortcuts.Recorder` controls for each global shortcut
/// defined in `HotkeyService`. Defaults match legacy PTHotKey defaults from
/// `legacy/Source/AppController.m +_defaultHotKeyCombos`.
struct ShortcutsPrefsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Clipboard menu", name: .openClipMenu)
                KeyboardShortcuts.Recorder("History menu", name: .openHistory)
                KeyboardShortcuts.Recorder("Snippets menu", name: .openSnippets)
                KeyboardShortcuts.Recorder("Actions menu", name: .openActions)
            } footer: {
                Text("These shortcuts open the ClipMenu status-bar menu. Defaults: ⌘⇧V, ⌘⌃V, ⌘⇧B, ⌘⇧A.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ShortcutsPrefsView()
        .frame(width: 520)
}

