import AppKit
import SwiftData
import SwiftUI

final class AppRuntime {
    static let shared = AppRuntime()

    let settings: ClipMenuSettings
    let clipsService: ClipsService
    let snippetService = SnippetService()
    let actionService = ActionService()
    let loginItemService = LoginItemService()
    let hotkeyService = HotkeyService()
    private let preferencesWindowController = PreferencesWindowController()
    private let welcomeWindowController = WelcomeWindowController()

    var modelContainer: ModelContainer?

    private init() {
        let settings = ClipMenuSettings()
        self.settings = settings
        clipsService = MainActor.assumeIsolated {
            PasteService.authorizePaste = {
                guard AppDistribution.usesAccessibility else { return false }
                return AutomaticPastePrompt.allowsPaste(settings: settings)
            }
            return ClipsService(settings: settings)
        }
    }

    /// A new library opens on Snippets so the first thing a person sees is a place
    /// to put the text they paste often. Accessibility is not requested here.
    @MainActor
    func presentGettingStartedIfNeeded(in context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        let showWelcome = args.contains("--show-welcome")
        guard showWelcome || !settings.didShowGettingStarted else { return }
        let automated = ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"
            || args.contains("--seed-clips")
            || args.contains("--open-hotkey-menu")
            || args.contains("--self-test-filter-slash")
            || args.contains("--self-test-action-menu")
        guard showWelcome || !automated else { return }
        if !showWelcome {
            settings.didShowGettingStarted = true
            let clipCount = (try? context.fetchCount(FetchDescriptor<ClipEntry>())) ?? 0
            guard clipCount == 0 else { return }
        }
        welcomeWindowController.show(
            onSetUpSnippets: { [weak self] in
                self?.showPreferences(tab: .snippets)
            }
        )
    }

    @MainActor
    func closePreferences() {
        preferencesWindowController.closeIfVisible()
    }

    @MainActor
    func showPreferences(tab: PreferencesTab = .general) {
        preferencesWindowController.show(
            settings: settings,
            loginItemService: loginItemService,
            modelContainer: modelContainer,
            initialTab: tab
        )
    }
}

@MainActor
private final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    func show(
        settings: ClipMenuSettings,
        loginItemService: LoginItemService,
        modelContainer: ModelContainer?,
        initialTab: PreferencesTab
    ) {
        let window = window ?? makeWindow()
        let rootView = makePreferencesView(
            settings: settings,
            loginItemService: loginItemService,
            modelContainer: modelContainer,
            initialTab: initialTab
        )
        window.contentViewController = NSHostingController(rootView: rootView)

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Hides Preferences once the user has left it. File panels keep it open.
    func closeIfVisible() {
        guard let window, window.isVisible, NSApp.modalWindow == nil else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppDistribution.displayName) Preferences"
        window.contentMinSize = NSSize(width: 680, height: 500)
        window.setFrameAutosaveName("Preferences")
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    private func makePreferencesView(
        settings: ClipMenuSettings,
        loginItemService: LoginItemService,
        modelContainer: ModelContainer?,
        initialTab: PreferencesTab
    ) -> AnyView {
        let rootView = PreferencesView(initialTab: initialTab)
            .environment(settings)
            .environment(\.loginItemService, loginItemService)

        if let modelContainer {
            return AnyView(rootView.modelContainer(modelContainer))
        }

        return AnyView(rootView)
    }
}

@MainActor
private final class WelcomeWindowController: NSWindowController {
    private var onSetUpSnippets: () -> Void = {}

    func show(onSetUpSnippets: @escaping () -> Void) {
        self.onSetUpSnippets = onSetUpSnippets
        let window = window ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: makeView())
        window.contentView?.layoutSubtreeIfNeeded()
        if let size = window.contentView?.fittingSize, size.width > 200, size.height > 160 {
            window.setContentSize(size)
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to \(AppDistribution.displayName)"
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }

    private func makeView() -> WelcomeView {
        WelcomeView(
            onSetUpSnippets: { [weak self] in
                self?.window?.close()
                self?.onSetUpSnippets()
            },
            onSkip: { [weak self] in
                self?.window?.close()
            }
        )
    }
}

private struct WelcomeView: View {
    var onSetUpSnippets: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to \(AppDistribution.displayName)")
                        .font(.system(size: 28, weight: .semibold))
                    Text("A place for the text you paste again and again.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Open \(AppDistribution.displayName) with ⌥⌘V. You can paste anything from your history, or from your favorite saved snippets. You can change the shortcut and how big your history is in the preferences.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(AppDistribution.displayName) does not save passwords.\nEverything it keeps is encrypted on your device and never leaves it.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(securityEmphasis)
                .fixedSize(horizontal: false, vertical: true)

            Text("Snippets are for an email address, a short bio, a reply you send all the time. The examples already in the list are placeholders. Replace them with your own.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Spacer()
                Button("Skip", action: onSkip)
                    .controlSize(.large)
                Button("Set Up Snippets", action: onSetUpSnippets)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(36)
        .frame(width: 640)
    }

    /// Brighter than the surrounding copy in both light and dark windows.
    private var securityEmphasis: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(srgbRed: 0.45, green: 0.86, blue: 1.0, alpha: 1)
            }
            return NSColor(srgbRed: 0.0, green: 0.32, blue: 0.98, alpha: 1)
        }))
    }
}
