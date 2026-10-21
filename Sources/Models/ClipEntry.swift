import SwiftData
import Foundation

/// A single clipboard entry captured from NSPasteboard.
///
/// Sensitive fields are stored in `sealedContent` (AES-GCM). The `stored*`
/// properties remain so a database from before encryption can be migrated,
/// then cleared. Equality / deduplication uses `contentHash`, which replicates
/// the algorithm from `legacy/Source/Clip.m -hash`.
@Model
final class ClipEntry {

    var createdAt: Date
    var lastUsedAt: Date

    /// AES-GCM combined box of a `ClipPayload`. Nil only for a row not yet migrated.
    var sealedContent: Data?

    @Attribute(originalName: "types") var storedTypes: [String]
    @Attribute(originalName: "stringValue") var storedStringValue: String?
    @Attribute(originalName: "rtfData") var storedRTFData: Data?
    @Attribute(originalName: "isRTFD") var storedIsRTFD: Bool
    @Attribute(originalName: "pdfData") var storedPDFData: Data?
    @Attribute(originalName: "filenames") var storedFilenames: [String]?
    @Attribute(originalName: "urlStrings") var storedURLStrings: [String]?
    @Attribute(originalName: "imageData") var storedImageData: Data?

    @Transient private var cachedPayload: ClipPayload?

    init() {
        createdAt = .now
        lastUsedAt = .now
        sealedContent = nil
        storedTypes = []
        storedStringValue = nil
        storedRTFData = nil
        storedIsRTFD = false
        storedPDFData = nil
        storedFilenames = nil
        storedURLStrings = nil
        storedImageData = nil
        cachedPayload = nil
        types = []
    }

    var types: [String] {
        get { payload().types }
        set { update { $0.types = newValue } }
    }

    var stringValue: String? {
        get { payload().stringValue }
        set { update { $0.stringValue = newValue } }
    }

    var rtfData: Data? {
        get { payload().rtfData }
        set { update { $0.rtfData = newValue } }
    }

    var isRTFD: Bool {
        get { payload().isRTFD }
        set { update { $0.isRTFD = newValue } }
    }

    var pdfData: Data? {
        get { payload().pdfData }
        set { update { $0.pdfData = newValue } }
    }

    var filenames: [String]? {
        get { payload().filenames }
        set { update { $0.filenames = newValue } }
    }

    var urlStrings: [String]? {
        get { payload().urlStrings }
        set { update { $0.urlStrings = newValue } }
    }

    var imageData: Data? {
        get { payload().imageData }
        set { update { $0.imageData = newValue } }
    }

    var contentHash: Int {
        let current = payload()
        var h = (current.types.joined() as NSString).hash
        if let imageData = current.imageData {
            h ^= imageData.count
        }
        if let filenames = current.filenames {
            for filename in filenames {
                h ^= (filename as NSString).hash
            }
        } else if let urlStrings = current.urlStrings {
            for urlString in urlStrings {
                h ^= (urlString as NSString).hash
            }
        } else if let pdfData = current.pdfData {
            h ^= pdfData.count
        } else if let stringValue = current.stringValue {
            h ^= (stringValue as NSString).hash
        }
        h ^= (current.rtfData?.count ?? 0)
        return h
    }

    /// Legacy hashes use byte lengths for binary data and can collide. Confirm
    /// every stored representation before discarding a newly captured clip.
    func hasSameContent(as other: ClipEntry) -> Bool {
        let lhs = payload()
        let rhs = other.payload()
        return lhs.types == rhs.types
            && lhs.stringValue == rhs.stringValue
            && lhs.isRTFD == rhs.isRTFD
            && lhs.rtfData == rhs.rtfData
            && lhs.pdfData == rhs.pdfData
            && lhs.filenames == rhs.filenames
            && lhs.urlStrings == rhs.urlStrings
            && lhs.imageData == rhs.imageData
    }

    /// Copies pre-encryption columns into `sealedContent` and clears them.
    /// A sealed row that cannot be authenticated is left untouched.
    func absorbLegacyPlaintext() throws -> Bool {
        let legacy = legacyPayload()
        if let sealedContent {
            let opened = try StoreEncryption.open(sealedContent, as: ClipPayload.self, domain: .history)
            // An empty sealed box must not discard plaintext that is still in
            // the pre-encryption columns.
            if !opened.hasSensitiveContent && legacy.hasSensitiveContent {
                self.sealedContent = try StoreEncryption.seal(legacy, domain: .history)
                cachedPayload = legacy
                clearLegacy()
                return true
            }
            guard legacy.hasSensitiveContent else { return false }
            clearLegacy()
            return true
        }
        guard legacy.hasSensitiveContent else { return false }
        sealedContent = try StoreEncryption.seal(legacy, domain: .history)
        cachedPayload = legacy
        clearLegacy()
        return true
    }

    private func payload() -> ClipPayload {
        if let cachedPayload { return cachedPayload }
        if let sealedContent, let opened = try? StoreEncryption.open(sealedContent, as: ClipPayload.self, domain: .history) {
            cachedPayload = opened
            return opened
        }
        if sealedContent != nil {
            let empty = ClipPayload()
            cachedPayload = empty
            return empty
        }
        let legacy = legacyPayload()
        cachedPayload = legacy
        return legacy
    }

    private func update(_ body: (inout ClipPayload) -> Void) {
        var next = payload()
        body(&next)
        guard let sealed = try? StoreEncryption.seal(next, domain: .history) else { return }
        sealedContent = sealed
        cachedPayload = next
        clearLegacy()
    }

    private func legacyPayload() -> ClipPayload {
        ClipPayload(
            types: storedTypes,
            stringValue: storedStringValue,
            rtfData: storedRTFData,
            isRTFD: storedIsRTFD,
            pdfData: storedPDFData,
            filenames: storedFilenames,
            urlStrings: storedURLStrings,
            imageData: storedImageData
        )
    }

    private var hasLegacyPlaintext: Bool {
        legacyPayload().hasSensitiveContent
    }

    private func clearLegacy() {
        storedTypes = []
        storedStringValue = nil
        storedRTFData = nil
        storedIsRTFD = false
        storedPDFData = nil
        storedFilenames = nil
        storedURLStrings = nil
        storedImageData = nil
    }
}
