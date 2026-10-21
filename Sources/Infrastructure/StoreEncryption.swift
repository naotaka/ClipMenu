import CryptoKit
import Foundation
import Security
import SwiftData

/// AES-GCM encryption for saved history and snippets.
///
/// History and snippets use different random keys so Clear History can retire
/// the history key without making snippets unreadable. There is no plaintext
/// fallback when a key cannot be used.
///
/// Both builds keep keys in the login Keychain, marked not synced, and
/// readable only while this Mac is unlocked. The data-protection Keychain
/// refuses a sandboxed development build that has no keychain entitlement
/// (`-34018`). Adding that entitlement without a provisioning profile makes
/// macOS kill the process, so the App Store build uses the login Keychain too.
/// Each build’s key is tied to its own store path, so the two copies do not
/// share history.
enum StoreEncryption {
    enum Domain: String {
        case history
        case snippets
    }

    enum Failure: LocalizedError {
        case keyUnavailable(OSStatus)
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .keyUnavailable(let status):
                return "The encryption key in the Keychain is not available (status \(status)). Unlock this Mac and open clip'M again. Saved data was not written in plain text."
            case .invalidPayload:
                return "Saved data could not be authenticated. clip'M did not fall back to an unencrypted copy."
            }
        }
    }

    private struct State {
        var storeURL: URL?
        var historyKey: SymmetricKey?
        var snippetKey: SymmetricKey?
        var ephemeralHistory: SymmetricKey?
        var ephemeralSnippets: SymmetricKey?
    }

    private static let lock = NSLock()
    private static var state = State()
    private static let service = "org.unitedvisions.ClipM.store"
    private static let needsVacuumName = ".needs-vacuum"

    /// The login Keychain works for the sandboxed App Store build and the
    /// unsandboxed direct build. See the type comment for why the
    /// data-protection Keychain is not used.
    private static var usesDataProtectionKeychain: Bool { false }

    /// Persistent store. The keychain account is tied to this file’s path.
    static func bindPersistent(storeURL: URL) throws {
        let canonical = canonicalURL(storeURL)
        lock.lock()
        state = State(storeURL: canonical, historyKey: nil, snippetKey: nil, ephemeralHistory: nil, ephemeralSnippets: nil)
        lock.unlock()
        _ = try key(for: .history)
        _ = try key(for: .snippets)
    }

    /// In-memory tests and previews. Never touches the Keychain.
    static func bindEphemeral() {
        lock.lock()
        state = State(
            storeURL: nil,
            historyKey: nil,
            snippetKey: nil,
            ephemeralHistory: SymmetricKey(size: .bits256),
            ephemeralSnippets: SymmetricKey(size: .bits256)
        )
        lock.unlock()
    }

    static func seal<T: Encodable>(_ value: T, domain: Domain) throws -> Data {
        let body = try PropertyListEncoder().encode(value)
        var plain = Data([1])
        plain.append(body)
        let box = try AES.GCM.seal(plain, using: try key(for: domain))
        guard let combined = box.combined else { throw Failure.invalidPayload }
        return combined
    }

    static func open<T: Decodable>(_ data: Data, as type: T.Type, domain: Domain) throws -> T {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: try key(for: domain))
        guard plain.first == 1 else { throw Failure.invalidPayload }
        return try PropertyListDecoder().decode(type, from: Data(plain.dropFirst()))
    }

    /// Deletes the keys for the bound persistent store. Tests use this so
    /// temporary store paths do not accumulate Keychain items.
    static func removeBoundKeys() {
        lock.lock()
        let storeURL = state.storeURL
        lock.unlock()
        guard let storeURL else { return }
        try? deleteKeychainItem(domain: .history, storeURL: storeURL)
        try? deleteKeychainItem(domain: .snippets, storeURL: storeURL)
        lock.lock()
        state.historyKey = nil
        state.snippetKey = nil
        lock.unlock()
    }

    /// Replaces the history key. Existing history ciphertext cannot be opened
    /// with the new key. The snippets key is left in place.
    static func rotateHistoryKey() throws {
        lock.lock()
        guard let storeURL = state.storeURL else {
            state.ephemeralHistory = SymmetricKey(size: .bits256)
            state.historyKey = nil
            lock.unlock()
            return
        }
        lock.unlock()
        try deleteKeychainItem(domain: .history, storeURL: storeURL)
        lock.lock()
        state.historyKey = nil
        lock.unlock()
        _ = try key(for: .history)
    }

    /// Encrypts rows that were saved before encryption existed, then asks
    /// SQLite to rebuild the file so those plaintext pages are dropped.
    @MainActor
    static func migratePlaintext(in context: ModelContext) throws {
        guard context.container.configurations.contains(where: { !$0.isStoredInMemoryOnly }) else { return }
        var changed = false
        for clip in try context.fetch(FetchDescriptor<ClipEntry>()) {
            if try clip.absorbLegacyPlaintext() { changed = true }
        }
        for folder in try context.fetch(FetchDescriptor<SnippetFolder>()) {
            if try folder.absorbLegacyPlaintext() { changed = true }
        }
        for snippet in try context.fetch(FetchDescriptor<Snippet>()) {
            if try snippet.absorbLegacyPlaintext() { changed = true }
        }
        let flag = needsVacuumURL(in: context)
        let pending = flag.flatMap { FileManager.default.fileExists(atPath: $0.path) } ?? false
        #if DEBUG
        fputs(
            "[clipM] store encryption clips=\(try context.fetchCount(FetchDescriptor<ClipEntry>())) folders=\(try context.fetchCount(FetchDescriptor<SnippetFolder>())) snippets=\(try context.fetchCount(FetchDescriptor<Snippet>())) rewritten=\(changed)\n",
            stderr
        )
        #endif
        guard changed || pending else { return }
        try context.save()
        do {
            try HistoryErasure.compactStore(in: context)
            if let flag { try? FileManager.default.removeItem(at: flag) }
        } catch {
            if let flag { try? Data().write(to: flag, options: .atomic) }
            throw error
        }
    }

    private static func key(for domain: Domain) throws -> SymmetricKey {
        lock.lock()
        if let storeURL = state.storeURL {
            if let cached = storedKeyLocked(domain) {
                lock.unlock()
                return cached
            }
            lock.unlock()
            // Keychain calls can wait on the user. Do not hold the lock.
            let loaded = try loadOrCreateKeychainKey(domain: domain, storeURL: storeURL)
            lock.lock()
            if state.storeURL == storeURL, storedKeyLocked(domain) == nil {
                switch domain {
                case .history: state.historyKey = loaded
                case .snippets: state.snippetKey = loaded
                }
            }
            let resolved = storedKeyLocked(domain) ?? loaded
            lock.unlock()
            return resolved
        }
        defer { lock.unlock() }
        switch domain {
        case .history:
            if let key = state.ephemeralHistory { return key }
            let key = SymmetricKey(size: .bits256)
            state.ephemeralHistory = key
            return key
        case .snippets:
            if let key = state.ephemeralSnippets { return key }
            let key = SymmetricKey(size: .bits256)
            state.ephemeralSnippets = key
            return key
        }
    }

    private static func storedKeyLocked(_ domain: Domain) -> SymmetricKey? {
        switch domain {
        case .history: state.historyKey
        case .snippets: state.snippetKey
        }
    }

    private static func loadOrCreateKeychainKey(domain: Domain, storeURL: URL) throws -> SymmetricKey {
        let account = accountName(domain: domain, storeURL: storeURL)
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            guard data.count == 32 else { throw Failure.invalidPayload }
            return SymmetricKey(data: data)
        }
        if status != errSecItemNotFound { throw Failure.keyUnavailable(status) }
        let created = SymmetricKey(size: .bits256)
        let createdData = keyData(created)
        var add = baseQuery(account: account)
        add[kSecValueData as String] = createdData
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecDuplicateItem {
            item = nil
            let again = SecItemCopyMatching(query as CFDictionary, &item)
            if again == errSecSuccess, let data = item as? Data, data.count == 32 {
                return SymmetricKey(data: data)
            }
        }
        guard added == errSecSuccess else { throw Failure.keyUnavailable(added) }
        return created
    }

    private static func deleteKeychainItem(domain: Domain, storeURL: URL) throws {
        let status = SecItemDelete(baseQuery(account: accountName(domain: domain, storeURL: storeURL)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keyUnavailable(status) }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        } else {
            query[kSecAttrSynchronizable as String] = false
        }
        return query
    }

    private static func accountName(domain: Domain, storeURL: URL) -> String {
        let digest = SHA256.hash(data: Data(canonicalURL(storeURL).path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(domain.rawValue).\(hex)"
    }

    private static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private static func canonicalURL(_ url: URL) -> URL {
        if let resolved = realpath(url.path, nil) {
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved))
        }
        return url.standardizedFileURL
    }

    private static func needsVacuumURL(in context: ModelContext) -> URL? {
        guard let url = context.container.configurations.first(where: { !$0.isStoredInMemoryOnly })?.url else {
            return nil
        }
        return url.deletingLastPathComponent().appendingPathComponent(needsVacuumName)
    }
}

struct ClipPayload: Codable {
    var types: [String] = []
    var stringValue: String?
    var rtfData: Data?
    var isRTFD: Bool = false
    var pdfData: Data?
    var filenames: [String]?
    var urlStrings: [String]?
    var imageData: Data?

    var hasSensitiveContent: Bool {
        !types.isEmpty || stringValue != nil || rtfData != nil || pdfData != nil
            || filenames != nil || urlStrings != nil || imageData != nil || isRTFD
    }
}

struct SnippetPayload: Codable {
    var title: String
    var content: String
}

struct SnippetFolderPayload: Codable {
    var title: String
}
