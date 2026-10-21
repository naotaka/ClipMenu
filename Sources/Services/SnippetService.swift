import SwiftData
import AppKit
import Foundation

/// CRUD operations over SnippetFolder / Snippet records.
///
/// Reference: `legacy/Source/SnippetsController.{h,m}`.
@MainActor
final class SnippetService {

    private var context: ModelContext?
    private let pasteService = PasteService()

    nonisolated init() {}

    func start(context: ModelContext) {
        self.context = context
        seedStarterSnippetsIfNeeded()
    }

    /// Example folders for a brand-new library, so the menu isn’t empty.
    /// A library that already has folders is left alone. The marker sits beside
    /// that library, because preferences can arrive from another copy whose
    /// database is not this one.
    private func seedStarterSnippetsIfNeeded() {
        guard let context else { return }
        let count = (try? context.fetchCount(FetchDescriptor<SnippetFolder>())) ?? 0
        let marker = starterSeedMarkerURL(in: context)
        if count > 0 {
            writeStarterSeedMarker(marker)
            return
        }
        if let marker, FileManager.default.fileExists(atPath: marker.path) { return }
        if marker == nil, UserDefaults.standard.bool(forKey: Self.starterSeedDefaultsKey) { return }

        let groups: [(String, [(String, String)])] = [
            ("me", [
                ("email", "you@example.com"),
                ("phone", "626-831-9333"),
                ("address", "123 Kindness Lane"),
                ("About me", "I like laughing and helping little old ladies cross the street."),
                ("name", "John Doe"),
            ]),
            ("dev", [
                ("ls", "ls"),
            ]),
            ("work", [
                ("Company Name", "United Visions"),
                ("Address", "1 Infinite Loop"),
            ]),
            ("hobbies", [
                ("Baskets", "I love to weave baskets with patterns that inspire kindness."),
                ("Ultimate Frisbee", "I love playing ultimate frisbee. It is the kindest, funnest game."),
            ]),
            ("affirmations", [
                ("I practice feeling great.", "I practice feeling great."),
                ("Kindness makes me strong.", "Kindness makes me strong."),
                ("I radiate so much goodwill that houseplants stand up straighter.", "I radiate so much goodwill that houseplants stand up straighter."),
                ("I write the thank-you I have been meaning to send.", "I write the thank-you I have been meaning to send."),
            ]),
        ]

        for (folderIndex, group) in groups.enumerated() {
            let folder = SnippetFolder(title: group.0, sortIndex: folderIndex)
            context.insert(folder)
            for (snippetIndex, item) in group.1.enumerated() {
                let snippet = Snippet(title: item.0, content: item.1, sortIndex: snippetIndex)
                snippet.folder = folder
                folder.snippets.append(snippet)
                context.insert(snippet)
            }
        }
        do {
            try context.save()
            writeStarterSeedMarker(marker)
            UserDefaults.standard.set(true, forKey: Self.starterSeedDefaultsKey)
        } catch {
            // Leave the library unmarked so the next launch can try again.
        }
    }

    private static let starterSeedDefaultsKey = "didSeedStarterSnippets"
    private static let starterSeedMarkerName = ".starter-snippets-seeded"

    private func starterSeedMarkerURL(in context: ModelContext) -> URL? {
        guard let url = context.container.configurations.first(where: { !$0.isStoredInMemoryOnly })?.url else {
            return nil
        }
        return url.deletingLastPathComponent().appendingPathComponent(Self.starterSeedMarkerName)
    }

    private func writeStarterSeedMarker(_ url: URL?) {
        guard let url else { return }
        try? Data().write(to: url, options: .atomic)
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
        await pasteService.paste()
    }
}
