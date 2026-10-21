import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

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
    /// While true, title keystrokes also update content (until the user edits content separately).
    @State private var mirroringTitleIntoContent = false
    @State private var lastMirroredTitle = ""
    /// Content edits are kept in-memory until selection changes (avoids save lag on every click).
    @State private var contentDirty = false
    @State private var importAlertTitle = ""
    @State private var importAlertMessage = ""
    @State private var showingImportAlert = false
    /// Grip under the pointer, used only to highlight that handle.
    @State private var draggableFolderID: PersistentIdentifier?
    @State private var draggableSnippetID: PersistentIdentifier?
    /// While true, every row in that list can be dragged and is a drop target.
    /// Arming only the grabbed row makes the other rows refuse the drop, so the
    /// item can only be released in the gap it already occupies.
    @State private var folderReorderArmed = false
    @State private var snippetReorderArmed = false
    @State private var reorderDragLock = ReorderDragLock()
    /// Bumped when + appends a row, so a long list scrolls until that row is visible.
    @State private var folderScrollTrigger = 0
    @State private var snippetScrollTrigger = 0
    @State private var handledFolderScrollTrigger = 0
    @State private var handledSnippetScrollTrigger = 0
    @State private var pendingFolderScrollID: PersistentIdentifier?
    @State private var pendingSnippetScrollID: PersistentIdentifier?

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
                    Text("The position to show snippets in \(AppDistribution.displayName):")
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
                    Text("The position to show snippets in \(AppDistribution.displayName):")
                    Picker("Snippet position", selection: $s.positionOfSnippets) {
                        Text("Above the clipboard history").tag(0)
                        Text("Below the clipboard history").tag(1)
                        Text("Hidden").tag(2)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("Anything that you paste regularly, you can keep as a snippet. So, descriptions of regular events that you host, or your personal bio. If you ever notice yourself writing the same thing more than once, turn it into a snippet. The examples already here are placeholders — replace them with your own email, address, and the lines you use often.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                foldersPane
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: .infinity)
                snippetsPane
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: .infinity)
                contentPane
                    .frame(minWidth: 220, idealWidth: 360, maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                Button("Export Snippets.xml…") {
                    exportLegacySnippetsFile()
                }
                .help("Saves your snippets as a Snippets.xml file. On another Mac, use Import Snippets.xml to bring them in.")
                Button("Import Snippets.xml…") {
                    importLegacySnippetsFile()
                }
                .help("Imports snippets. Either export them from ClipM, or for the old ClipMenu copy ~/Library/Application Support/ClipMenu/Snippets.xml - duplicate snippets will not be imported.")
            }
        }
        .padding()
        .onAppear { ensureSelection() }
        .onChange(of: folders.count) { _, _ in ensureSelection() }
        .onDisappear {
            commitFolderRenameIfNeeded()
            commitSnippetRenameIfNeeded()
            flushContentIfNeeded()
            persist()
        }
        .alert(importAlertTitle, isPresented: $showingImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importAlertMessage)
        }
    }

    private var foldersPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders")
                .font(.headline)

            VStack(spacing: 8) {
                ScrollViewReader { proxy in
                    List {
                        ForEach(folders) { folder in
                            reorderableRow(
                                gripActive: draggableFolderID == folder.persistentModelID,
                                onGripHover: { hovering in
                                    setReorderHover(
                                        $draggableFolderID,
                                        armed: $folderReorderArmed,
                                        id: folder.persistentModelID,
                                        hovering: hovering
                                    )
                                }
                            ) {
                                folderRow(folder)
                            }
                            .moveDisabled(!folderReorderArmed)
                            .id(folder.persistentModelID)
                            .listRowBackground(rowBackground(isSelected: folder.persistentModelID == selectedFolderID))
                            .accessibilityAction(named: Text("Move Up")) {
                                shift(Array(folders), moving: folder.persistentModelID, by: -1, sort: \.sortIndex)
                            }
                            .accessibilityAction(named: Text("Move Down")) {
                                shift(Array(folders), moving: folder.persistentModelID, by: 1, sort: \.sortIndex)
                            }
                            .background {
                                ListEndScroller(trigger: folderScrollTrigger, handledTrigger: $handledFolderScrollTrigger)
                                    .frame(width: 1, height: 1)
                                    .allowsHitTesting(false)
                            }
                            .onAppear {
                                focusNewRowIfNeeded(pendingFolderScrollID, rowID: folder.persistentModelID) {
                                    pendingFolderScrollID = nil
                                    isFolderNameFocused = true
                                }
                            }
                        }
                        .onMove(perform: moveFolders)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: folderScrollTrigger) { _, trigger in
                        revealAppendedRow(trigger: trigger, id: pendingFolderScrollID, proxy: proxy)
                    }
                }

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

            if selectedFolder != nil {
                VStack(spacing: 8) {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(selectedSnippets) { snippet in
                                reorderableRow(
                                    gripActive: draggableSnippetID == snippet.persistentModelID,
                                    onGripHover: { hovering in
                                        setReorderHover(
                                            $draggableSnippetID,
                                            armed: $snippetReorderArmed,
                                            id: snippet.persistentModelID,
                                            hovering: hovering
                                        )
                                    }
                                ) {
                                    snippetRow(snippet)
                                }
                                .moveDisabled(!snippetReorderArmed)
                                .id(snippet.persistentModelID)
                                .listRowBackground(rowBackground(isSelected: snippet.persistentModelID == selectedSnippetID))
                                .accessibilityAction(named: Text("Move Up")) {
                                    shift(selectedSnippets, moving: snippet.persistentModelID, by: -1, sort: \.sortIndex)
                                }
                                .accessibilityAction(named: Text("Move Down")) {
                                    shift(selectedSnippets, moving: snippet.persistentModelID, by: 1, sort: \.sortIndex)
                                }
                                .background {
                                    ListEndScroller(trigger: snippetScrollTrigger, handledTrigger: $handledSnippetScrollTrigger)
                                        .frame(width: 1, height: 1)
                                        .allowsHitTesting(false)
                                }
                                .onAppear {
                                    focusNewRowIfNeeded(pendingSnippetScrollID, rowID: snippet.persistentModelID) {
                                        pendingSnippetScrollID = nil
                                        isSnippetNameFocused = true
                                    }
                                }
                            }
                            .onMove(perform: moveSnippets)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: snippetScrollTrigger) { _, trigger in
                            revealAppendedRow(trigger: trigger, id: pendingSnippetScrollID, proxy: proxy)
                        }
                    }

                    ControlGroup {
                        Button(action: {
                            guard let selectedFolder else { return }
                            addSnippet(to: selectedFolder)
                        }) {
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
                    if mirroringTitleIntoContent, newValue != lastMirroredTitle {
                        mirroringTitleIntoContent = false
                    }
                    selectedSnippet.content = newValue
                    contentDirty = true
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

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.clear
    }

    /// Grip sits outside the row's click and rename gestures, which would otherwise swallow the drag.
    private func reorderableRow<Content: View>(
        gripActive: Bool,
        onGripHover: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gripActive ? Color.primary : Color.secondary)
                .frame(width: 16, height: 20)
                .contentShape(Rectangle())
                .onHover(perform: onGripHover)
                .help("Drag to reorder")
                .accessibilityLabel("Reorder")
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setReorderHover(
        _ hoveredID: Binding<PersistentIdentifier?>,
        armed: Binding<Bool>,
        id: PersistentIdentifier,
        hovering: Bool
    ) {
        if hovering {
            hoveredID.wrappedValue = id
            armed.wrappedValue = true
            NSCursor.openHand.set()
        } else if hoveredID.wrappedValue == id {
            let finish = {
                hoveredID.wrappedValue = nil
                armed.wrappedValue = false
                NSCursor.arrow.set()
            }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                finish()
            } else {
                // Hover ends when the drag starts. Keep every row droppable until the mouse is released.
                reorderDragLock.endWhenMouseUp(finish)
            }
        }
    }

    private func revealAppendedRow(trigger: Int, id: PersistentIdentifier?, proxy: ScrollViewProxy) {
        guard trigger > 0, let id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func focusNewRowIfNeeded(
        _ pendingID: PersistentIdentifier?,
        rowID: PersistentIdentifier,
        focus: @escaping () -> Void
    ) {
        guard pendingID == rowID else { return }
        // Defer so the scroll request still sees the pending id, and so the title field exists.
        DispatchQueue.main.async(execute: focus)
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        commitFolderRenameIfNeeded()
        reorder(Array(folders), from: source, to: destination, sort: \.sortIndex)
    }

    private func moveSnippets(from source: IndexSet, to destination: Int) {
        commitSnippetRenameIfNeeded()
        reorder(selectedSnippets, from: source, to: destination, sort: \.sortIndex)
    }

    private func shift<T: PersistentModel>(
        _ items: [T],
        moving id: PersistentIdentifier,
        by delta: Int,
        sort sortKey: ReferenceWritableKeyPath<T, Int>
    ) {
        commitFolderRenameIfNeeded()
        commitSnippetRenameIfNeeded()
        guard let index = items.firstIndex(where: { $0.persistentModelID == id }) else { return }
        let destination = index + delta
        guard items.indices.contains(destination) else { return }
        var ordered = items
        ordered.swapAt(index, destination)
        applySortOrder(ordered, sort: sortKey)
    }

    private func reorder<T: AnyObject>(
        _ items: [T],
        from source: IndexSet,
        to destination: Int,
        sort sortKey: ReferenceWritableKeyPath<T, Int>
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ items.indices.contains($0) }),
              (0...items.count).contains(destination)
        else { return }
        var ordered = items
        ordered.move(fromOffsets: source, toOffset: destination)
        applySortOrder(ordered, sort: sortKey)
    }

    private func applySortOrder<T: AnyObject>(
        _ ordered: [T],
        sort sortKey: ReferenceWritableKeyPath<T, Int>
    ) {
        var changed = false
        for (index, item) in ordered.enumerated() where item[keyPath: sortKey] != index {
            item[keyPath: sortKey] = index
            changed = true
        }
        if changed {
            persist()
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: SnippetFolder) -> some View {
        HStack(spacing: 6) {
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
                    .onExitCommand { commitFolderRename(folder) }
            } else {
                Text(folder.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help(folder.title)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        // Only the selected row listens for double-click rename. Otherwise SwiftUI
        // delays every single-click ~300ms waiting to see if a second tap is coming.
        .onTapGesture {
            guard editingFolderID != folder.persistentModelID else { return }
            selectFolder(folder)
        }
        .onDoubleClickWhen(selectedFolderID == folder.persistentModelID) {
            guard editingFolderID != folder.persistentModelID else { return }
            beginFolderRename(folder)
        }
    }

    @ViewBuilder
    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(spacing: 6) {
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
                    .onExitCommand { commitSnippetRename(snippet) }
                    .onChange(of: editingSnippetTitle) { _, newTitle in
                        mirrorTitleIntoContentIfNeeded(snippet, title: newTitle)
                    }
            } else {
                Text(snippet.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help(snippet.title)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard editingSnippetID != snippet.persistentModelID else { return }
            selectSnippet(snippet)
        }
        .onDoubleClickWhen(selectedSnippetID == snippet.persistentModelID) {
            guard editingSnippetID != snippet.persistentModelID else { return }
            beginSnippetRename(snippet)
        }
    }

    private func selectFolder(_ folder: SnippetFolder) {
        guard selectedFolderID != folder.persistentModelID else { return }
        commitFolderRenameIfNeeded()
        commitSnippetRenameIfNeeded()
        flushContentIfNeeded()
        selectedFolderID = folder.persistentModelID
        if !folder.snippets.contains(where: { $0.persistentModelID == selectedSnippetID }) {
            selectedSnippetID = folder.snippets.sorted { $0.sortIndex < $1.sortIndex }.first?.persistentModelID
        }
    }

    private func selectSnippet(_ snippet: Snippet) {
        guard selectedSnippetID != snippet.persistentModelID else { return }
        commitSnippetRenameIfNeeded()
        flushContentIfNeeded()
        selectedSnippetID = snippet.persistentModelID
    }

    private func flushContentIfNeeded() {
        guard contentDirty else { return }
        contentDirty = false
        persist()
    }

    private func addFolder() {
        commitFolderRenameIfNeeded()
        commitSnippetRenameIfNeeded()
        let nextIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        let folder = SnippetFolder(title: "New Folder", sortIndex: nextIndex)
        modelContext.insert(folder)
        persist()
        selectedFolderID = folder.persistentModelID
        selectedSnippetID = nil
        beginFolderRename(folder)
        pendingFolderScrollID = folder.persistentModelID
        folderScrollTrigger += 1
    }

    private func removeSelectedFolder() {
        guard let selectedFolder else { return }
        commitFolderRenameIfNeeded()
        commitSnippetRenameIfNeeded()
        modelContext.delete(selectedFolder)
        persist()
        selectedFolderID = nil
        selectedSnippetID = nil
        ensureSelection()
    }

    private func addSnippet(to folder: SnippetFolder) {
        commitSnippetRenameIfNeeded()
        let nextIndex = (folder.snippets.map(\.sortIndex).max() ?? -1) + 1
        let snippet = Snippet(title: "New Snippet", content: "New Snippet", sortIndex: nextIndex)
        snippet.folder = folder
        folder.snippets.append(snippet)
        modelContext.insert(snippet)
        persist()
        selectedSnippetID = snippet.persistentModelID
        beginSnippetRename(snippet, mirrorContent: true)
        pendingSnippetScrollID = snippet.persistentModelID
        snippetScrollTrigger += 1
    }

    private func removeSelectedSnippet() {
        guard let selectedSnippet else { return }
        commitSnippetRenameIfNeeded()
        modelContext.delete(selectedSnippet)
        persist()
        selectedSnippetID = selectedSnippets.first?.persistentModelID
    }

    private func exportLegacySnippetsFile() {
        commitFolderRenameIfNeeded()
        commitSnippetRenameIfNeeded()
        flushContentIfNeeded()
        persist()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Snippets.xml"
        panel.prompt = "Export"
        panel.message = "Save a Snippets.xml file you can import on another Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try LegacyMigration.exportSnippets(to: url, from: modelContext)
            importAlertTitle = "Snippets Exported"
            importAlertMessage = "Saved \(url.lastPathComponent). On the other Mac, open Preferences → Snippets and choose Import Snippets.xml."
        } catch {
            importAlertTitle = "Couldn’t Export Snippets"
            importAlertMessage = error.localizedDescription
        }
        showingImportAlert = true
    }

    private func importLegacySnippetsFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        panel.message = "Choose a Snippets.xml file from the original ClipMenu app."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let result: SnippetXMLImportResult
        do {
            result = try LegacyMigration.importSnippets(from: url, into: modelContext)
        } catch LegacyMigration.ImportFailure.unreadable {
            importAlertTitle = "Couldn’t Import Snippets"
            importAlertMessage = "macOS blocked reading that file. Allow clip'M to access Desktop and Downloads in System Settings → Privacy & Security → Files and Folders, then try again."
            showingImportAlert = true
            return
        } catch {
            importAlertTitle = "Couldn’t Import Snippets"
            importAlertMessage = "That file isn’t a ClipMenu Snippets.xml file."
            showingImportAlert = true
            return
        }

        importAlertTitle = "Snippets Imported"
        if result.snippetsAdded == 0 && result.snippetsSkipped == 0 {
            importAlertMessage = "That file doesn’t contain any snippets."
        } else if result.snippetsAdded == 0 {
            importAlertMessage = "Those snippets are already in the library."
        } else {
            let added = result.snippetsAdded == 1 ? "1 snippet" : "\(result.snippetsAdded) snippets"
            let folders = result.foldersAdded == 1 ? "1 new folder" : "\(result.foldersAdded) new folders"
            var message = "Added \(added) in \(folders)."
            if result.snippetsSkipped > 0 {
                let skipped = result.snippetsSkipped == 1 ? "1 snippet was" : "\(result.snippetsSkipped) snippets were"
                message += " \(skipped) already there."
            }
            importAlertMessage = message
        }
        showingImportAlert = true
        ensureSelection()
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
        commitFolderRenameIfNeeded()
        selectedFolderID = folder.persistentModelID
        editingFolderID = folder.persistentModelID
        editingFolderTitle = folder.title
        DispatchQueue.main.async {
            isFolderNameFocused = true
        }
    }

    private func commitFolderRenameIfNeeded() {
        guard let editingFolderID,
              let folder = folders.first(where: { $0.persistentModelID == editingFolderID })
        else {
            editingFolderID = nil
            return
        }
        commitFolderRename(folder)
    }

    private func commitFolderRename(_ folder: SnippetFolder) {
        guard editingFolderID == folder.persistentModelID else { return }
        let trimmed = editingFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.title = trimmed.isEmpty ? folder.title : trimmed
        editingFolderID = nil
        isFolderNameFocused = false
        persist()
    }

    private func beginSnippetRename(_ snippet: Snippet, mirrorContent: Bool = false) {
        commitSnippetRenameIfNeeded()
        selectedSnippetID = snippet.persistentModelID
        editingSnippetID = snippet.persistentModelID
        editingSnippetTitle = snippet.title

        let trimmedContent = snippet.content.trimmingCharacters(in: .whitespacesAndNewlines)
        mirroringTitleIntoContent = mirrorContent
            || trimmedContent.isEmpty
            || snippet.content == snippet.title
        lastMirroredTitle = snippet.title
        if mirroringTitleIntoContent, snippet.content != snippet.title {
            snippet.content = snippet.title
            lastMirroredTitle = snippet.title
        }

        DispatchQueue.main.async {
            isSnippetNameFocused = true
        }
    }

    private func mirrorTitleIntoContentIfNeeded(_ snippet: Snippet, title: String) {
        guard mirroringTitleIntoContent else { return }
        if !snippet.content.isEmpty, snippet.content != lastMirroredTitle {
            mirroringTitleIntoContent = false
            return
        }
        snippet.content = title
        lastMirroredTitle = title
        contentDirty = true
    }

    private func commitSnippetRenameIfNeeded() {
        guard let editingSnippetID,
              let snippet = selectedSnippets.first(where: { $0.persistentModelID == editingSnippetID })
                ?? folders.lazy.flatMap(\.snippets).first(where: { $0.persistentModelID == editingSnippetID })
        else {
            editingSnippetID = nil
            mirroringTitleIntoContent = false
            return
        }
        commitSnippetRename(snippet)
    }

    private func commitSnippetRename(_ snippet: Snippet) {
        guard editingSnippetID == snippet.persistentModelID else { return }
        let trimmed = editingSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = trimmed.isEmpty ? snippet.title : trimmed
        snippet.title = newTitle

        if mirroringTitleIntoContent || snippet.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snippet.content = newTitle
        }

        editingSnippetID = nil
        isSnippetNameFocused = false
        mirroringTitleIntoContent = false
        persist()
    }
}

// MARK: - Preview

#Preview {
    let folder = SnippetFolder(title: "Templates", sortIndex: 0)
    let snippet = Snippet(title: "Greeting", content: "Hello from clip'M!", sortIndex: 0)
    snippet.folder = folder
    folder.snippets = [snippet]

    return SnippetsPrefsView()
        .modelContainer(for: [SnippetFolder.self, Snippet.self], inMemory: true)
}

/// Scrolls the enclosing list to its last row when `trigger` changes.
/// SwiftUI `List` on macOS is often an `NSTableView`, which ignores `ScrollViewReader`.
private struct ListEndScroller: NSViewRepresentable {
    var trigger: Int
    @Binding var handledTrigger: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.trigger = trigger
        context.coordinator.handled = $handledTrigger
        context.coordinator.schedule(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var trigger = 0
        var handled: Binding<Int> = .constant(0)
        var pending = false

        func schedule(from view: NSView) {
            guard trigger > 0, trigger != handled.wrappedValue, !pending else { return }
            pending = true
            attempt(view: view, remaining: 8)
        }

        private func attempt(view: NSView, remaining: Int) {
            DispatchQueue.main.async { [weak view] in
                guard self.trigger != self.handled.wrappedValue else {
                    self.pending = false
                    return
                }
                guard let view, Self.scrollToEnd(from: view) else {
                    guard remaining > 0, let view else {
                        self.pending = false
                        return
                    }
                    self.attempt(view: view, remaining: remaining - 1)
                    return
                }
                self.handled.wrappedValue = self.trigger
                self.pending = false
                // The new row can land a beat after the first successful scroll.
                for delay in [0.0, 0.05, 0.15] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                        guard let view else { return }
                        _ = Self.scrollToEnd(from: view)
                    }
                }
            }
        }

        private static func scrollToEnd(from view: NSView) -> Bool {
            guard let table = tableView(from: view) else { return false }
            let row = table.numberOfRows - 1
            guard row >= 0 else { return false }
            table.scrollRowToVisible(row)
            return true
        }

        private static func tableView(from view: NSView) -> NSTableView? {
            var current: NSView? = view
            while let candidate = current {
                if let table = candidate as? NSTableView { return table }
                current = candidate.superview
            }
            return nil
        }
    }
}

/// Clears a reorder session on mouse-up. A drag leaves the grip, so hover-exit
/// cannot turn dropping off until the button is released.
private final class ReorderDragLock {
    var monitor: Any?

    func endWhenMouseUp(_ body: @escaping () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                body()
                if let monitor = self.monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
            return event
        }
    }
}

private extension View {
    /// Attaches a double-click handler only when `enabled` is true, so unselected
    /// rows are not slowed down by SwiftUI's double-tap recognition window.
    @ViewBuilder
    func onDoubleClickWhen(_ enabled: Bool, perform: @escaping () -> Void) -> some View {
        if enabled {
            simultaneousGesture(TapGesture(count: 2).onEnded { perform() })
        } else {
            self
        }
    }
}
