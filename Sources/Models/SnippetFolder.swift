import Foundation
import SwiftData

@Model
final class SnippetFolder {

    var isEnabled: Bool
    var sortIndex: Int

    /// AES-GCM combined box of a `SnippetFolderPayload`.
    var sealedContent: Data?

    @Attribute(originalName: "title") var storedTitle: String?

    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder)
    var snippets: [Snippet] = []

    @Transient private var cachedTitle: String?

    init(title: String, sortIndex: Int = 0) {
        self.isEnabled = true
        self.sortIndex = sortIndex
        self.sealedContent = nil
        self.storedTitle = nil
        self.cachedTitle = nil
        self.title = title
    }

    var title: String {
        get {
            if let cachedTitle { return cachedTitle }
            if let sealedContent, let opened = try? StoreEncryption.open(sealedContent, as: SnippetFolderPayload.self, domain: .snippets) {
                cachedTitle = opened.title
                return opened.title
            }
            if sealedContent != nil { return "" }
            cachedTitle = storedTitle
            return storedTitle ?? ""
        }
        set {
            guard let sealed = try? StoreEncryption.seal(SnippetFolderPayload(title: newValue), domain: .snippets) else { return }
            sealedContent = sealed
            cachedTitle = newValue
            storedTitle = nil
        }
    }

    func absorbLegacyPlaintext() throws -> Bool {
        let legacyTitle = storedTitle
        if let sealedContent {
            let opened = try StoreEncryption.open(sealedContent, as: SnippetFolderPayload.self, domain: .snippets)
            if let legacyTitle, !legacyTitle.isEmpty, opened.title.isEmpty {
                self.sealedContent = try StoreEncryption.seal(SnippetFolderPayload(title: legacyTitle), domain: .snippets)
                cachedTitle = legacyTitle
                storedTitle = nil
                return true
            }
            guard legacyTitle != nil else { return false }
            storedTitle = nil
            return true
        }
        guard let legacyTitle else { return false }
        sealedContent = try StoreEncryption.seal(SnippetFolderPayload(title: legacyTitle), domain: .snippets)
        cachedTitle = legacyTitle
        storedTitle = nil
        return true
    }
}
