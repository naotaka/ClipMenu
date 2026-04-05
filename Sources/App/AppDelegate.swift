import AppKit

/// Lifecycle hooks that must live in an NSApplicationDelegate rather than the
/// SwiftUI App struct (e.g. applicationWillTerminate, Sparkle delegate).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure persisted settings are hydrated and normalized before services read them.
        runtime.settings.reload()

        // Register global hotkeys immediately. This should not depend on
        // SwiftData container readiness.
        runtime.hotkeyService.register()

        do {
            try runtime.loginItemService.setEnabled(runtime.settings.launchAtLogin)
        } catch {
            // Keep startup resilient when login item registration fails.
        }

        startDataServicesWhenReady(retryCount: 10)
    }

    @MainActor
    private func startDataServicesWhenReady(retryCount: Int) {
        guard let modelContext = runtime.modelContainer?.mainContext else {
            guard retryCount > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                startDataServicesWhenReady(retryCount: retryCount - 1)
            }
            return
        }

        if LegacyMigration.isNeeded {
            LegacyMigration.run(in: modelContext)
        }

        Task {
            runtime.clipsService.start(context: modelContext)
            await runtime.snippetService.start(context: modelContext)
            await runtime.actionService.start(context: modelContext)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.hotkeyService.unregister()
        Task {
            runtime.clipsService.stop()
        }
    }
}
