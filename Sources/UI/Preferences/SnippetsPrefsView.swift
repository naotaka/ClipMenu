import SwiftUI
import SwiftData

/// Snippets tab in the Preferences window.
///
/// Provides basic folder/snippet editing so users can manage items shown
/// in the Snippets menu.
struct SnippetsPrefsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipMenuSettings.self) private var settings

    @Query(sort: \SnippetFolder.sortIndex) private var folders: [SnippetFolder]

    @State private var selectedFolderID: PersistentIdentifier?
    @State private var selectedSnippetID: PersistentIdentifier?
    @State private var editingFolderID: PersistentIdentifier?
    @State private var editingFolderTitle: String = ""
    @State private var editingSnippetID: PersistentIdentifier?
    @State private var editingSnippetTitle: String = ""

    @FocusState private var isFolderNameFocused: Bool
    @FocusState private var isSnippetNameFocused: Bool

    private var selectedFolder: SnippetFolder? {
        folders.first { $0.persistentModelID == selectedFolderID }
    }

    private var selectedSnippets: [Snippet] {
        guard let selectedFolder else { return [] }
        return selectedFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var selectedSnippet: Snippet? {
        selectedSnippets.first { $0.persistentModelID == selectedSnippetID }
    }

    var body: some View {
        @Bindable var s = settings

        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("The position to show snippets in ClipMenu:")
                    Spacer()
                    Picker("Snippet position", selection: $s.positionOfSnippets) {
                        Text("Above the clipboard history").tag(0)
                        Text("Below the clipboard history").tag(1)
                        Text("Hidden").tag(2)
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("The position to show snippets in ClipMenu:")
                    Picker("Snippet position", selection: $s.positionOfSnippets) {
                        Text("Above the clipboard history").tag(0)
                        Text("Below the clipboard history").tag(1)
                        Text("Hidden").tag(2)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                foldersPane
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: .infinity)
                snippetsPane
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: .infinity)
                contentPane
                    .frame(minWidth: 220, idealWidth: 360, maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .onAppear { ensureSelection() }
        .onChange(of: folders.count) { _, _ in ensureSelection() }
        .onChange(of: selectedFolderID) { _, _ in
            guard let selectedFolder else {
                selectedSnippetID = nil
                return
            }
            if !selectedFolder.snippets.contains(where: { $0.persistentModelID == selectedSnippetID }) {
                selectedSnippetID = selectedFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }.first?.persistentModelID
            }
            editingSnippetID = nil
        }
    }

    private var foldersPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders")
                .font(.headline)

            VStack(spacing: 8) {
                List {
                    ForEach(folders) { folder in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { folder.isEnabled },
                                set: { newValue in
                                    folder.isEnabled = newValue
                                    persist()
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                            Image(systemName: "folder.fill")

                            if editingFolderID == folder.persistentModelID {
                                TextField("Folder", text: $editingFolderTitle)
                                    .textFieldStyle(.plain)
                                    .focused($isFolderNameFocused)
                                    .onSubmit { commitFolderRename(folder) }
                            } else {
                                Text(folder.title)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFolderID = folder.persistentModelID
                        }
                        .onTapGesture(count: 2) {
                            beginFolderRename(folder)
                        }
                        .listRowBackground(folder.persistentModelID == selectedFolderID ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ControlGroup {
                    Button(action: addFolder) {
                        Image(systemName: "plus")
                    }
                    .help("Add Folder")

                    Button(action: removeSelectedFolder) {
                        Image(systemName: "minus")
                    }
                    .help("Remove Folder")
                    .disabled(selectedFolder == nil)
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var snippetsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.headline)

            if let selectedFolder {
                VStack(spacing: 8) {
                    List {
                        ForEach(selectedSnippets) { snippet in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { snippet.isEnabled },
                                    set: { newValue in
                                        snippet.isEnabled = newValue
                                        persist()
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                                if editingSnippetID == snippet.persistentModelID {
                                    TextField("Title", text: $editingSnippetTitle)
                                        .textFieldStyle(.plain)
                                        .focused($isSnippetNameFocused)
                                        .onSubmit { commitSnippetRename(snippet) }
                                } else {
                                    Text(snippet.title)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSnippetID = snippet.persistentModelID
                            }
                            .onTapGesture(count: 2) {
                                beginSnippetRename(snippet)
                            }
                            .listRowBackground(snippet.persistentModelID == selectedSnippetID ? Color.accentColor.opacity(0.15) : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ControlGroup {
                        Button(action: { addSnippet(to: selectedFolder) }) {
                            Image(systemName: "plus")
                        }
                        .help("Add Snippet")

                        Button(action: removeSelectedSnippet) {
                            Image(systemName: "minus")
                        }
                        .help("Remove Snippet")
                        .disabled(selectedSnippet == nil)
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ContentUnavailableView("No Folder Selected", systemImage: "text.badge.plus", description: Text("Create a folder to start adding snippets."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                    .background(panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.headline)

            TextEditor(text: Binding(
                get: { selectedSnippet?.content ?? "" },
                set: { newValue in
                    guard let selectedSnippet else { return }
                    selectedSnippet.content = newValue
                    persist()
                }
            ))
            .frame(minHeight: 280, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .padding(8)
            .disabled(selectedSnippet == nil)
        }
        .padding(10)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var panelBackground: Color {
        Color.black.opacity(0.1)
    }

    private func addFolder() {
        let nextIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        let folder = SnippetFolder(title: "New Folder", sortIndex: nextIndex)
        modelContext.insert(folder)
        persist()
        selectedFolderID = folder.persistentModelID
        selectedSnippetID = nil
        beginFolderRename(folder)
    }

    private func removeSelectedFolder() {
        guard let selectedFolder else { return }
        modelContext.delete(selectedFolder)
        persist()
        selectedFolderID = nil
        selectedSnippetID = nil
        ensureSelection()
    }

    private func addSnippet(to folder: SnippetFolder) {
        let nextIndex = (folder.snippets.map(\.sortIndex).max() ?? -1) + 1
        let snippet = Snippet(title: "New Snippet", content: "", sortIndex: nextIndex)
        snippet.folder = folder
        folder.snippets.append(snippet)
        modelContext.insert(snippet)
        persist()
        selectedSnippetID = snippet.persistentModelID
        beginSnippetRename(snippet)
    }

    private func removeSelectedSnippet() {
        guard let selectedSnippet else { return }
        modelContext.delete(selectedSnippet)
        persist()
        selectedSnippetID = selectedSnippets.first?.persistentModelID
    }

    private func ensureSelection() {
        if selectedFolder == nil {
            selectedFolderID = folders.first?.persistentModelID
        }

        guard let selectedFolder else {
            selectedSnippetID = nil
            return
        }

        if !selectedFolder.snippets.contains(where: { $0.persistentModelID == selectedSnippetID }) {
            selectedSnippetID = selectedFolder.snippets.sorted { $0.sortIndex < $1.sortIndex }.first?.persistentModelID
        }
    }

    private func persist() {
        try? modelContext.save()
    }

    private func beginFolderRename(_ folder: SnippetFolder) {
        selectedFolderID = folder.persistentModelID
        editingFolderID = folder.persistentModelID
        editingFolderTitle = folder.title
        isFolderNameFocused = true
    }

    private func commitFolderRename(_ folder: SnippetFolder) {
        let trimmed = editingFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.title = trimmed.isEmpty ? folder.title : trimmed
        editingFolderID = nil
        persist()
    }

    private func beginSnippetRename(_ snippet: Snippet) {
        selectedSnippetID = snippet.persistentModelID
        editingSnippetID = snippet.persistentModelID
        editingSnippetTitle = snippet.title
        isSnippetNameFocused = true
    }

    private func commitSnippetRename(_ snippet: Snippet) {
        let trimmed = editingSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        snippet.title = trimmed.isEmpty ? snippet.title : trimmed
        editingSnippetID = nil
        persist()
    }
}

// MARK: - Preview

#Preview {
    let folder = SnippetFolder(title: "Templates", sortIndex: 0)
    let snippet = Snippet(title: "Greeting", content: "Hello from ClipMenu!", sortIndex: 0)
    snippet.folder = folder
    folder.snippets = [snippet]

    return SnippetsPrefsView()
        .modelContainer(for: [SnippetFolder.self, Snippet.self], inMemory: true)
}
