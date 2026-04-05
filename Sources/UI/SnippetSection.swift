import SwiftUI
import AppKit

/// Renders enabled snippet folders and their snippets as menu submenus.
///
/// Mirrors `legacy/Source/MenuController.m` snippet menu construction.
struct SnippetSection: View {

    /// Pre-filtered to enabled folders only (ClipMenuView does the filtering).
    let folders: [SnippetFolder]

    @Environment(\.clipsService) private var clipsService

    var body: some View {
        ForEach(folders) { folder in
            let enabled = folder.snippets
                .filter(\.isEnabled)
                .sorted { $0.sortIndex < $1.sortIndex }
            if !enabled.isEmpty {
                Menu {
                    ForEach(enabled) { snippet in
                        snippetButton(snippet)
                    }
                } label: {
                    Label(folder.title, systemImage: "folder")
                }
            }
        }
    }

    private func snippetButton(_ snippet: Snippet) -> some View {
        Button(snippet.title) {
            Task {
                await clipsService.copyStringToPasteboard(snippet.content)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let folder1 = SnippetFolder(title: "Greetings", sortIndex: 0)
    let s1 = Snippet(title: "Hello", content: "Hello, world!", sortIndex: 0)
    let s2 = Snippet(title: "Goodbye", content: "Goodbye!", sortIndex: 1)
    s1.folder = folder1
    s2.folder = folder1
    folder1.snippets = [s1, s2]

    let folder2 = SnippetFolder(title: "Lone snippet", sortIndex: 1)
    let s3 = Snippet(title: "Quick note", content: "FYI", sortIndex: 0)
    s3.folder = folder2
    folder2.snippets = [s3]

    return SnippetSection(folders: [folder1, folder2])
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .padding()
}
