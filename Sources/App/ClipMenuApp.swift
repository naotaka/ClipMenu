import SwiftUI
import SwiftData
import AppKit

@main
struct ClipMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let runtime = AppRuntime.shared
    private let isPasteUITestMode = ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"

    init() {
        let schema = Schema([
            ClipEntry.self,
            SnippetFolder.self,
            Snippet.self,
            ActionNode.self,
        ])

        let configuration: ModelConfiguration
        if isPasteUITestMode {
            StoreEncryption.bindEphemeral()
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            do {
                // Set only when migrating a copy of the store. Normal launches ignore it.
                let supportOverride = ProcessInfo.processInfo.environment["CLIPMENU_SUPPORT_DIRECTORY"]
                    .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
                let storeURL = try ClipStoreLocation.prepareURL(in: supportOverride)
                try StoreEncryption.bindPersistent(storeURL: storeURL)
                configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            } catch {
                _ = NSApplication.shared
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "\(AppDistribution.displayName) couldn’t open its saved data."
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Quit")
                alert.runModal()
                exit(1)
            }
        }
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            if !isPasteUITestMode {
                try ClipStoreLocation.protectStoreFiles(in: configuration.url.deletingLastPathComponent())
                try StoreEncryption.migratePlaintext(in: modelContainer.mainContext)
            }
        } catch {
            // Never discard a user's history or snippets to recover from a
            // store-open failure. Report it instead of crashing on a force-try.
            _ = NSApplication.shared
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "\(AppDistribution.displayName) couldn’t open its saved data."
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            exit(1)
        }
        runtime.modelContainer = modelContainer
    }

    var body: some Scene {
        Settings {
            PreferencesView()
                .modelContainer(modelContainer)
                .environment(runtime.settings)
                .environment(\.loginItemService, runtime.loginItemService)
        }
        .modelContainer(modelContainer)
    }
}
