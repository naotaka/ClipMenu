import SwiftUI

/// Menu tab in the Preferences window.
///
/// Covers: title length, inline/folder counts, numbering, labels,
/// clear-history item, tooltips, font size, thumbnails, icons.
/// Reference: `legacy/Source/PrefsWindowController.{h,m}` Menu tab.
struct MenuPrefsView: View {

    @Environment(ClipMenuSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        Form {
            // MARK: Title display
            Section("Title Display") {
                LabeledContent("Max title length") {
                    TextField("", value: $s.maxMenuItemTitleLength, format: .number)
                        .frame(width: 60)
                }
                Toggle("Prefix items with numbers", isOn: $s.numberedMenuItems)
                Toggle("Start numbering at zero", isOn: $s.numberingStartsAtZero)
                    .disabled(!settings.numberedMenuItems)
                Toggle("Add numeric key equivalents (1–0)", isOn: $s.numericKeyEquivalents)
                Toggle("Show type label in title", isOn: $s.showLabelsInMenu)
            }

            // MARK: Layout
            Section("Layout") {
                LabeledContent("Items shown inline") {
                    TextField("", value: $s.numberOfItemsInline, format: .number)
                        .frame(width: 60)
                }
                LabeledContent("Items per subfolder") {
                    TextField("", value: $s.numberOfItemsInsideFolder, format: .number)
                        .frame(width: 60)
                }
                Picker("Snippet position", selection: $s.positionOfSnippets) {
                    Text("Above clips").tag(0)
                    Text("Below clips").tag(1)
                    Text("Hidden").tag(2)
                }
            }

            // MARK: Misc items
            Section("Menu Items") {
                Toggle("Show \"Clear History\" item", isOn: $s.showClearHistoryItem)
                Toggle("Confirm before clearing", isOn: $s.showAlertBeforeClearHistory)
                    .disabled(!settings.showClearHistoryItem)
            }

            // MARK: Tooltips
            Section("Tooltips") {
                Toggle("Show tooltip on hover", isOn: $s.showTooltipsInMenu)
                LabeledContent("Max tooltip length") {
                    TextField("", value: $s.maxTooltipLength, format: .number)
                        .frame(width: 80)
                }
                .disabled(!settings.showTooltipsInMenu)
            }

            // MARK: Font
            Section("Font Size") {
                Toggle("Override menu font size", isOn: $s.changeFontSize)
                if settings.changeFontSize {
                    Picker("Mode", selection: $s.fontSizeMode) {
                        Text("Match icon size").tag(0)
                        Text("Manual").tag(1)
                    }
                    .pickerStyle(.radioGroup)
                    if settings.fontSizeMode == 1 {
                        LabeledContent("Font size (pt)") {
                            TextField("", value: $s.selectedFontSize, format: .number)
                                .frame(width: 60)
                        }
                    }
                }
            }

            // MARK: Images
            Section("Images") {
                Toggle("Show image thumbnails", isOn: $s.showImageInMenu)
                if settings.showImageInMenu {
                    LabeledContent("Thumbnail width (px)") {
                        TextField("", value: $s.thumbnailWidth, format: .number)
                            .frame(width: 60)
                    }
                    LabeledContent("Thumbnail height (px)") {
                        TextField("", value: $s.thumbnailHeight, format: .number)
                            .frame(width: 60)
                    }
                }
            }

            // MARK: Icons
            Section("Type Icons") {
                Toggle("Show type icon", isOn: $s.showIconInMenu)
                if settings.showIconInMenu {
                    Picker("Icon size", selection: $s.menuIconSize) {
                        Text("16 px").tag(16)
                        Text("32 px").tag(32)
                        Text("48 px").tag(48)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    MenuPrefsView()
        .environment(ClipMenuSettings())
        .frame(width: 520)
}
