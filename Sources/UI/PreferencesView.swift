import SwiftUI

enum PreferencesTab: Hashable, CaseIterable, Identifiable {
    case general
    case menu
    case snippets
    case actions
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .menu: return "Menu"
        case .snippets: return "Snippets"
        case .actions: return "Actions"
        case .shortcuts: return "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .menu: return "list.bullet"
        case .snippets: return "text.badge.plus"
        case .actions: return "bolt"
        case .shortcuts: return "keyboard"
        }
    }
}

/// Root of the Settings scene — tabbed preferences window.
///
/// Mirrors the tab structure from `legacy/Source/PrefsWindowController.{h,m}`
/// (General, Menu, Actions, Shortcuts tabs).
struct PreferencesView: View {
    @State private var selection: PreferencesTab

    init(initialTab: PreferencesTab = .general) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(PreferencesTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            Label(tab.title, systemImage: tab.symbolName)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(selection == tab ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selection == tab ? Color.accentColor : Color.clear)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Group {
                switch selection {
                case .general:
                    GeneralPrefsView()
                case .menu:
                    MenuPrefsView()
                case .snippets:
                    SnippetsPrefsView()
                case .actions:
                    ActionsPrefsView()
                case .shortcuts:
                    ShortcutsPrefsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, minHeight: 500)
        .padding(12)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
        .environment(ClipMenuSettings())
        .environment(\.loginItemService, LoginItemService())
}
