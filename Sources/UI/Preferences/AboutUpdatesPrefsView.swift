import SwiftUI
import AppKit

/// About + Updates tab. Channel-specific update controls; shared branding links.
struct AboutUpdatesPrefsView: View {
    @Environment(ClipMenuSettings.self) private var settings
    @StateObject private var appStoreChecker = AppStoreUpdateChecker()
#if canImport(Sparkle)
    @ObservedObject private var sparkle = SparkleUpdateService.shared
#endif

    private var isCheckingAppStore: Bool {
        if case .checking = appStoreChecker.status { return true }
        return false
    }

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("About") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppDistribution.displayName)
                                .font(.title2.weight(.semibold))
                            Text(AppDistribution.byline)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(AppDistribution.versionLabel)
                                .foregroundStyle(.secondary)
                            Text(AppDistribution.channelDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(AppDistribution.aboutBlurb)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 16) {
                        Link("GitHub", destination: AppDistribution.githubURL)
                        Link(AppDistribution.unitedVisionsName, destination: AppDistribution.unitedVisionsURL)
                        Link("Privacy Policy", destination: AppDistribution.privacyPolicyURL)
                    }
                    .font(.body.weight(.medium))
                }
                .padding(.vertical, 4)
            }

            Section("Updates") {
                if AppDistribution.isAppStoreBuild {
                    appStoreUpdatesSection
                } else {
                    directUpdatesSection
                }
            }
        }
        .formStyle(.grouped)
        .padding()
#if canImport(Sparkle)
        .onAppear {
            sparkle.applySettings(settings)
        }
        .onChange(of: s.enableAutomaticCheck) { _, _ in
            sparkle.applySettings(settings)
        }
        .onChange(of: s.updateCheckInterval) { _, _ in
            sparkle.applySettings(settings)
        }
#endif
    }

    @ViewBuilder
    private var appStoreUpdatesSection: some View {
        Text("This copy was installed from the Mac App Store. Updates are delivered through the App Store.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        statusText(for: appStoreChecker.status)

        HStack {
            Button("Check for Updates") {
                Task { await appStoreChecker.check() }
            }
            .disabled(isCheckingAppStore)

            if case .updateAvailable(_, let url) = appStoreChecker.status {
                Button("Update in App Store") {
                    appStoreChecker.openStorePage(fallback: url)
                }
                .keyboardShortcut(.defaultAction)
            } else if case .notListed = appStoreChecker.status {
                Button("Open App Store") {
                    appStoreChecker.openStorePage()
                }
            }
        }
    }

    @ViewBuilder
    private var directUpdatesSection: some View {
        @Bindable var s = settings

        Text("This copy supports in-app updates for GitHub / direct downloads.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

#if canImport(Sparkle)
        Toggle("Automatically check for updates", isOn: $s.enableAutomaticCheck)

        LabeledContent("Check interval") {
            Picker("", selection: $s.updateCheckInterval) {
                Text("Every day").tag(86_400)
                Text("Every week").tag(604_800)
                Text("Every month").tag(2_592_000)
            }
            .labelsHidden()
            .frame(width: 160)
            .disabled(!s.enableAutomaticCheck)
        }

        Button("Check for Updates…") {
            sparkle.checkForUpdates()
        }
#else
        Text("Sparkle is not linked in this build. Download the latest release from GitHub.")
            .foregroundStyle(.secondary)
        Link(
            "Open GitHub Releases",
            destination: AppDistribution.githubURL.appending(path: "releases")
        )
#endif
    }

    @ViewBuilder
    private func statusText(for status: AppStoreUpdateChecker.Status) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking the App Store…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .upToDate(let storeVersion):
            Label("You’re up to date (App Store \(storeVersion)).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .updateAvailable(let storeVersion, _):
            Label("Version \(storeVersion) is available on the App Store.", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.primary)
        case .notListed:
            Text("\(AppDistribution.displayName) isn’t listed on the App Store for this bundle ID yet (or the listing isn’t public). You can still open the App Store to search.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    AboutUpdatesPrefsView()
        .environment(ClipMenuSettings())
        .frame(width: 560, height: 520)
}
