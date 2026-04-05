import SwiftData
import AppKit
import Foundation

/// CRUD operations over SnippetFolder / Snippet records.
///
/// Reference: `legacy/Source/SnippetsController.{h,m}`.
actor SnippetService {

    private var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
    }

    func folders() throws -> [SnippetFolder] {
        guard let context else { return [] }
        return try context.fetch(FetchDescriptor<SnippetFolder>(sortBy: [SortDescriptor(\SnippetFolder.sortIndex)]))
    }

    func createFolder(title: String) throws -> SnippetFolder {
        guard let context else { return SnippetFolder(title: title, sortIndex: 0) }
        let current = try folders()
        let folder = SnippetFolder(title: title, sortIndex: current.count)
        context.insert(folder)
        try context.save()
        return folder
    }

    func updateFolder(_ folder: SnippetFolder, title: String? = nil, isEnabled: Bool? = nil) throws {
        if let title {
            folder.title = title
        }
        if let isEnabled {
            folder.isEnabled = isEnabled
        }
        try context?.save()
    }

    func deleteFolder(_ folder: SnippetFolder) throws {
        context?.delete(folder)
        try context?.save()
    }

    func createSnippet(in folder: SnippetFolder, title: String, content: String = "") throws -> Snippet {
        let sortIndex = folder.snippets.map(\.sortIndex).max().map { $0 + 1 } ?? 0
        let snippet = Snippet(title: title, content: content, sortIndex: sortIndex)
        snippet.folder = folder
        context?.insert(snippet)
        try context?.save()
        return snippet
    }

    func updateSnippet(_ snippet: Snippet, title: String? = nil, content: String? = nil, isEnabled: Bool? = nil) throws {
        if let title {
            snippet.title = title
        }
        if let content {
            snippet.content = content
        }
        if let isEnabled {
            snippet.isEnabled = isEnabled
        }
        try context?.save()
    }

    func deleteSnippet(_ snippet: Snippet) throws {
        context?.delete(snippet)
        try context?.save()
    }

    func moveSnippet(_ snippet: Snippet, to folder: SnippetFolder, at index: Int) throws {
        snippet.folder = folder
        snippet.sortIndex = max(index, 0)
        try context?.save()
    }

    func paste(snippet: Snippet) async {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.setString(snippet.content, forType: .string)
        await PasteService().paste()
    }
}
