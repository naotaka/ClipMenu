import AppKit
import Combine

/// Publishes `NSPasteboard` change events as a Combine stream.
///
/// Uses a timer-based polling approach (matching legacy behaviour) rather than
/// KVO, because NSPasteboard does not expose a reliable change notification API.
/// Check `legacy/Source/ClipsController.m` for the polling interval and the
/// change-count comparison logic before changing this implementation.
final class ClipboardMonitor {
    let pasteboardChanged = PassthroughSubject<NSPasteboard, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

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
                self.pasteboardChanged.send(self.pasteboard)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }
}
