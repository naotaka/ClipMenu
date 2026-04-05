import SwiftData

@Model
final class SnippetFolder {

    var title: String
    var isEnabled: Bool
    var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder)
    var snippets: [Snippet] = []

    init(title: String, sortIndex: Int = 0) {
        self.title     = title
        self.isEnabled = true
        self.sortIndex = sortIndex
    }
}
