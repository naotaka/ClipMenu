import SwiftData

@Model
final class Snippet {

    var title: String
    var content: String
    var isEnabled: Bool
    var sortIndex: Int

    var folder: SnippetFolder?

    init(title: String, content: String = "", sortIndex: Int = 0) {
        self.title     = title
        self.content   = content
        self.isEnabled = true
        self.sortIndex = sortIndex
    }
}
