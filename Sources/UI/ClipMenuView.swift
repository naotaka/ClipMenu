import SwiftUI
import SwiftData

/// Root content of the status-bar MenuBarExtra.
///
/// Mirrors the menu hierarchy from `legacy/Source/MenuController.m -buildClipMenu`.
struct ClipMenuView: View {
    private let runtime = AppRuntime.shared

    @Query(sort: \ClipEntry.lastUsedAt, order: .reverse) private var clips: [ClipEntry]
    @Query(sort: \SnippetFolder.sortIndex) private var folders: [SnippetFolder]
    @Query(
        filter: #Predicate<ActionNode> { $0.parent == nil },
        sort: \ActionNode.sortIndex
    ) private var rootActions: [ActionNode]

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.clipsService) private var clipsService
    @Environment(\.snippetService) private var snippetService

    var body: some View {
        // Snippets above clips
        if settings.positionOfSnippets == 0 {
            SnippetSection(folders: folders.filter(\.isEnabled))
            Divider()
        }

        // Clip history rows
        clipsSection

        // Snippets below clips (default)
        if settings.positionOfSnippets == 1 {
            Divider()
            SnippetSection(folders: folders.filter(\.isEnabled))
        }

        if settings.enableAction {
            Divider()
            Menu {
                if let targetClip = clips.first {
                    let enabledRoots = rootActions.filter(\.isEnabled)
                    if enabledRoots.isEmpty {
                        Text("No actions configured")
                    } else {
                        ActionSection(nodes: enabledRoots, target: targetClip)
                    }
                } else {
                    Text("No clips available")
                }
            } label: {
                Label("Actions", systemImage: "bolt")
            }
        }

        // Clear History
        if settings.showClearHistoryItem {
            Divider()
            Button(action: clearHistory) {
                Label("Clear History", systemImage: "trash")
            }
        }

        Divider()

        Button {
            runtime.showPreferences(tab: .snippets)
        } label: {
            Label("Edit Snippets…", systemImage: "text.badge.plus")
        }
        Button {
            runtime.showPreferences()
        } label: {
            Label("Preferences…", systemImage: "gearshape")
        }
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit ClipMenu", systemImage: "power")
        }
    }

    // MARK: - Clips section

    // Computed outside @ViewBuilder so SwiftUI's dependency tracking reliably
    // sees the @Query `clips` property on every render.

    private var inlineClips: [ClipEntry] {
        let n = settings.numberOfItemsInline
        let capped = Array(clips.prefix(max(settings.maxHistorySize, 0)))
        // Legacy: n == 0 → all items go into folder submenus (mirrors ObjC behaviour).
        return n == 0 ? [] : Array(capped.prefix(n))
    }

    /// Groups of clips that appear inside folder submenus.
    private var folderGroups: [[ClipEntry]] {
        let n = settings.numberOfItemsInline
        let groupSize = max(settings.numberOfItemsInsideFolder, 1)
        let capped = Array(clips.prefix(max(settings.maxHistorySize, 0)))
        let remaining = n == 0 ? capped : Array(capped.dropFirst(n))
        guard !remaining.isEmpty else { return [] }
        return stride(from: 0, to: remaining.count, by: groupSize).map {
            Array(remaining[$0..<min($0 + groupSize, remaining.count)])
        }
    }

    @ViewBuilder
    private var clipsSection: some View {
        let inlineCount = settings.numberOfItemsInline
        let groupSize   = max(settings.numberOfItemsInsideFolder, 1)

        ForEach(Array(inlineClips.enumerated()), id: \.element.id) { index, clip in
            ClipMenuItem(entry: clip, listNumber: listNumber(for: index))
        }

        ForEach(Array(folderGroups.enumerated()), id: \.offset) { groupIndex, group in
            let start = inlineCount + groupIndex * groupSize + 1
            let end   = start + group.count - 1
            Menu {
                ForEach(Array(group.enumerated()), id: \.element.id) { idx, clip in
                    ClipMenuItem(
                        entry: clip,
                        listNumber: listNumber(for: inlineCount + groupIndex * groupSize + idx)
                    )
                }
            } label: {
                Label("\(start) – \(end)", systemImage: "folder")
            }
        }
    }

    // MARK: - Helpers

    /// Replicates the numbering logic from legacy MenuController (starting at 0 or 1, wrapping at 10).
    private func listNumber(for index: Int) -> Int {
        if settings.numberingStartsAtZero {
            return index % 10
        } else {
            let n = index + 1
            return n > 10 ? n % 10 : n
        }
    }

    private func clearHistory() {
        if settings.showAlertBeforeClearHistory {
            let alert = NSAlert()
            alert.messageText = "Clear History"
            alert.informativeText = "Are you sure you want to clear all clipboard history?"
            alert.addButton(withTitle: "Clear")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task { try? await clipsService.clearAll() }
    }
}

// MARK: - Preview

#Preview {
    ClipMenuView()
        .environment(ClipMenuSettings())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .environment(\.snippetService, SnippetService())
        .modelContainer(for: [ClipEntry.self, SnippetFolder.self, Snippet.self, ActionNode.self],
                        inMemory: true)
}
