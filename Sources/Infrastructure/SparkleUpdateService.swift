#if canImport(Sparkle)
import Foundation
import Sparkle

/// Thin wrapper around Sparkle for direct-download (non–App Store) builds.
@MainActor
final class SparkleUpdateService: NSObject, ObservableObject {
    static let shared = SparkleUpdateService()

    let controller: SPUStandardUpdaterController

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { controller.updater.updateCheckInterval }
        set { controller.updater.updateCheckInterval = newValue }
    }

    func applySettings(_ settings: ClipMenuSettings) {
        automaticallyChecksForUpdates = settings.enableAutomaticCheck
        updateCheckInterval = TimeInterval(max(settings.updateCheckInterval, 3600))
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
