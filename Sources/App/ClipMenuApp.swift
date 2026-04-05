import SwiftUI
import SwiftData

@main
struct ClipMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let runtime = AppRuntime.shared

    init() {
        let schema = Schema([
            ClipEntry.self,
            SnippetFolder.self,
            Snippet.self,
            ActionNode.self,
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        runtime.modelContainer = modelContainer
    }

    var body: some Scene {
        MenuBarExtra {
            ClipMenuView()
                .modelContainer(modelContainer)
                .environment(runtime.settings)
                .environment(\.clipsService, runtime.clipsService)
                .environment(\.snippetService, runtime.snippetService)
                .environment(\.actionService, runtime.actionService)
        } label: {
            Image(systemName: "clipboard.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityLabel("ClipMenu")
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(modelContainer)

        Settings {
            PreferencesView()
                .modelContainer(modelContainer)
                .environment(runtime.settings)
                .environment(\.loginItemService, runtime.loginItemService)
        }
        .modelContainer(modelContainer)
    }
}

