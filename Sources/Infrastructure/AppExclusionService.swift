import AppKit

/// Provides the bundle identifier of the currently frontmost application so
/// that ClipsService can skip recording clipboard changes triggered by ClipMenu
/// itself.
///
/// Mirrors `legacy/Source/AppController.m -frontmostApplicationBundleIdentifier`.
final class AppExclusionService {

    private var excludedIDs = Set<String>()

    func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func update(from settings: ClipMenuSettings) {
        excludedIDs = Set(settings.excludeApps.compactMap { $0["bundleIdentifier"] })
    }

    /// Returns `true` when clipboard changes should be ignored because
    /// the frontmost app is in the exclusion list stored in user preferences.
    func shouldExclude(observedBundleIdentifier: String? = nil, declaredBundleIdentifiers: [String] = []) -> Bool {
        // A declared source is only an additional reason to reject a copy. It
        // is supplied by another process and must never override an exclusion.
        let candidates = declaredBundleIdentifiers
            + [observedBundleIdentifier, frontmostBundleIdentifier()].compactMap { $0 }
        return candidates.contains { excludedIDs.contains($0) }
    }

    func runningUserApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName, let id = app.bundleIdentifier else { return nil }
                return (name: name, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
