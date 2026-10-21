import Foundation

/// Distribution channel and public links shared by About / Updates UI.
enum AppDistribution {
    /// User-facing product name (Finder, About, menus).
    static let displayName = "clip'M"

    /// Short marketing line used under the name where space allows.
    static let byline = "Full featured copy paste manager for M chip Macs"

    /// Compile-time channel. Direct (GitHub) builds omit `APP_STORE`.
    static var isAppStoreBuild: Bool {
        #if APP_STORE
        true
        #else
        false
        #endif
    }

    /// The direct download may use Accessibility to send Command-V. The Mac App
    /// Store build must not request or use that permission (Guideline 2.4.5).
    static var usesAccessibility: Bool { !isAppStoreBuild }

    static var channelDisplayName: String {
        isAppStoreBuild ? "Mac App Store" : "Direct download"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionLabel: String {
        "Version \(shortVersion) (\(buildNumber))"
    }

    /// Open-source repository (safe to link from App Store builds as source/docs).
    static let githubURL = URL(string: "https://github.com/Frazer/clipM")!

    static let unitedVisionsURL = URL(string: "https://unitedvisions.org")!
    static let unitedVisionsName = "United Visions"

    static let privacyPolicyURL = URL(string: "https://frazer.github.io/clipM/privacy.html")!

    /// Set this once the app is listed (numeric App Store ID). Used to deep-link the product page.
    static let appStoreProductID: String? = "6818600547"

    /// Sparkle appcast for direct builds. Host this file on GitHub Releases (or your site).
    static let sparkleFeedURL = URL(string: "https://github.com/Frazer/clipM/releases/latest/download/appcast.xml")!

    static var aboutBlurb: String {
        """
        \(byline).

        \(displayName) keeps clipboard history, snippets, and actions at your fingertips from the menu bar.

        This project is open source. Source code and direct-download releases live on GitHub. \(displayName) is supported by \(unitedVisionsName), which helps you train your mind to be the best version of yourself.

        Thanks to ClipMenu for the original design this work builds on.

        \(displayName) does not track any of your information. Your settings and data stay entirely on your machine. Saved history and snippets are encrypted on this Mac.
        """
    }
}
