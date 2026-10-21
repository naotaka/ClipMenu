import Foundation
import AppKit

/// Checks the public iTunes Lookup API for a newer Mac App Store version.
@MainActor
final class AppStoreUpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(storeVersion: String)
        case updateAvailable(storeVersion: String, storeURL: URL)
        case notListed
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private let bundleID: String
    private let session: URLSession

    init(
        bundleID: String = Bundle.main.bundleIdentifier ?? "org.unitedvisions.ClipM",
        session: URLSession = .shared
    ) {
        self.bundleID = bundleID
        self.session = session
    }

    func check() async {
        status = .checking

        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "macSoftware"),
        ]
        guard let url = components?.url else {
            status = .failed("Could not build App Store lookup URL.")
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                status = .failed("App Store lookup failed (\(http.statusCode)).")
                return
            }

            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let match = decoded.results.first(where: { $0.bundleId == bundleID }) else {
                status = .notListed
                return
            }

            let storeVersion = match.version
            let storeURL = resolvedStoreURL(from: match)

            if Self.isVersion(storeVersion, newerThan: AppDistribution.shortVersion) {
                status = .updateAvailable(storeVersion: storeVersion, storeURL: storeURL)
            } else {
                status = .upToDate(storeVersion: storeVersion)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func openStorePage(fallback url: URL? = nil) {
        if let url, Self.isStoreURL(url) {
            NSWorkspace.shared.open(url)
            return
        }
        if let id = AppDistribution.appStoreProductID,
           let deepLink = URL(string: "macappstore://apps.apple.com/app/id\(id)") {
            NSWorkspace.shared.open(deepLink)
            return
        }
        let query = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "clipM"
        if let search = URL(string: "macappstore://itunes.apple.com/search?term=\(query)&entity=macSoftware") {
            NSWorkspace.shared.open(search)
        }
    }

    private func resolvedStoreURL(from match: LookupResult) -> URL {
        if let id = AppDistribution.appStoreProductID,
           let deepLink = URL(string: "macappstore://apps.apple.com/app/id\(id)") {
            return deepLink
        }
        if let trackID = match.trackId, trackID > 0,
           let deepLink = URL(string: "macappstore://apps.apple.com/app/id\(trackID)") {
            return deepLink
        }
        if let page = match.trackViewUrl, let https = URL(string: page), Self.isStoreURL(https) {
            return https
        }
        return AppDistribution.githubURL
    }

    /// Network-provided links may open only the Apple store, never local files
    /// or arbitrary application URL handlers.
    static func isStoreURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["https", "macappstore"].contains(scheme),
              let host = components.host?.lowercased(),
              ["apps.apple.com", "itunes.apple.com"].contains(host),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { return false }
        return true
    }

    /// Simple dotted numeric compare: `1.2.0` > `1.1.9`.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map(String.init)
        let right = rhs.split(separator: ".").map(String.init)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : "0"
            let r = index < right.count ? right[index] : "0"
            if let li = Int(l), let ri = Int(r) {
                if li != ri { return li > ri }
            } else if l != r {
                return l > r
            }
        }
        return false
    }
}

private struct LookupResponse: Decodable {
    let results: [LookupResult]
}

private struct LookupResult: Decodable {
    let bundleId: String
    let version: String
    let trackViewUrl: String?
    let trackId: Int?
}
