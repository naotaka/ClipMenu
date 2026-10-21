import Foundation
import SwiftData

@Model
final class Snippet {

    var isEnabled: Bool
    var sortIndex: Int

    /// AES-GCM combined box of a `SnippetPayload`.
    var sealedContent: Data?

    @Attribute(originalName: "title") var storedTitle: String?
    @Attribute(originalName: "content") var storedContent: String?

    var folder: SnippetFolder?

    @Transient private var cachedPayload: SnippetPayload?

    init(title: String, content: String = "", sortIndex: Int = 0) {
        self.isEnabled = true
        self.sortIndex = sortIndex
        self.sealedContent = nil
        self.storedTitle = nil
        self.storedContent = nil
        self.cachedPayload = nil
        self.title = title
        self.content = content
    }

    var title: String {
        get { payload().title }
        set { update { $0.title = newValue } }
    }

    var content: String {
        get { payload().content }
        set { update { $0.content = newValue } }
    }

    func absorbLegacyPlaintext() throws -> Bool {
        let legacyTitle = storedTitle
        let legacyContent = storedContent
        let hasLegacy = legacyTitle != nil || legacyContent != nil
        if let sealedContent {
            let opened = try StoreEncryption.open(sealedContent, as: SnippetPayload.self, domain: .snippets)
            let legacyHasText = !(legacyTitle ?? "").isEmpty || !(legacyContent ?? "").isEmpty
            if hasLegacy && legacyHasText && opened.title.isEmpty && opened.content.isEmpty {
                let legacy = SnippetPayload(title: legacyTitle ?? "", content: legacyContent ?? "")
                self.sealedContent = try StoreEncryption.seal(legacy, domain: .snippets)
                cachedPayload = legacy
                storedTitle = nil
                storedContent = nil
                return true
            }
            guard hasLegacy else { return false }
            storedTitle = nil
            storedContent = nil
            return true
        }
        guard hasLegacy else { return false }
        let legacy = SnippetPayload(title: legacyTitle ?? "", content: legacyContent ?? "")
        sealedContent = try StoreEncryption.seal(legacy, domain: .snippets)
        cachedPayload = legacy
        storedTitle = nil
        storedContent = nil
        return true
    }

    private func payload() -> SnippetPayload {
        if let cachedPayload { return cachedPayload }
        if let sealedContent, let opened = try? StoreEncryption.open(sealedContent, as: SnippetPayload.self, domain: .snippets) {
            cachedPayload = opened
            return opened
        }
        if sealedContent != nil {
            let empty = SnippetPayload(title: "", content: "")
            cachedPayload = empty
            return empty
        }
        let legacy = SnippetPayload(title: storedTitle ?? "", content: storedContent ?? "")
        cachedPayload = legacy
        return legacy
    }

    private func update(_ body: (inout SnippetPayload) -> Void) {
        var next = payload()
        body(&next)
        guard let sealed = try? StoreEncryption.seal(next, domain: .snippets) else { return }
        sealedContent = sealed
        cachedPayload = next
        storedTitle = nil
        storedContent = nil
    }
}
