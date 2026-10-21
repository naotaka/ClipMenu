import AppKit
import Combine

/// Publishes `NSPasteboard` change events as a Combine stream.
///
/// Uses a timer-based polling approach (matching legacy behaviour) rather than
/// KVO, because NSPasteboard does not expose a reliable change notification API.
/// Check `legacy/Source/ClipsController.m` for the polling interval and the
/// change-count comparison logic before changing this implementation.
final class ClipboardMonitor {
    struct Change {
        let pasteboard: NSPasteboard
        let changeCount: Int
        let sourceBundleIdentifier: String?
    }

    let pasteboardChanged = PassthroughSubject<Change, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var lastChangeCount: Int = 0
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func ignoreCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.75) {
        stop()
        lastChangeCount = pasteboard.changeCount

        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let current = self.pasteboard.changeCount
                guard current != self.lastChangeCount else { return }
                self.lastChangeCount = current
                self.pasteboardChanged.send(Change(
                    pasteboard: self.pasteboard,
                    changeCount: current,
                    sourceBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                ))
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }
}
