import SwiftUI
import SwiftData
import Foundation

/// Actions tab in the Preferences window.
///
/// Covers: enable toggle, action-menu modifier key, invoke-immediately,
/// and the action menu editor.
struct ActionsPrefsView: View {

    @Environment(ClipMenuSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ActionNode> { $0.parent == nil },
           sort: \ActionNode.sortIndex)
    private var rootNodes: [ActionNode]

    @State private var selectedNodeToken: String?
    @State private var selectedCatalogID: String?
    @State private var rightTab: RightTab = .builtin
    @State private var editingNodeID: PersistentIdentifier?
    @State private var editingTitle: String = ""
    @State private var expandedFolderTokens: Set<String> = []
    @State private var expandedCatalogFolderIDs: Set<String> = []
    @FocusState private var isInlineNameFocused: Bool
    /// Bumped when user scripts on disk change so the User's catalog reloads.
    @State private var catalogEpoch = 0

    @State private var scriptTitle = ""
    @State private var scriptBody = ""
    @State private var scriptFileURL: URL?
    @State private var scriptIsEditable = false
    @State private var scriptHasChanges = false
    @State private var scriptPlaceholder: String? = "Select a JavaScript action to view or edit its source."
    @State private var scriptError: String?

    private enum RightTab: String, CaseIterable {
        case builtin = "Built-in"
        case javaScript = "JavaScript"
        case users = "User's"
    }

    private struct AvailableActionItem: Identifiable, Hashable {
        var id: String
        var name: String
        var actionType: String
        var actionName: String?
        var scriptPath: String?
    }

    private struct CatalogNode: Identifiable, Hashable {
        var id: String
        var name: String
        var isLeaf: Bool
        var item: AvailableActionItem?
        var children: [CatalogNode]

        var visibleChildren: [CatalogNode]? {
            children.isEmpty ? nil : children
        }
    }

    var body: some View {
        @Bindable var s = settings
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Right-click a clip or snippet to trigger actions menu.")
                        Text("Or use this action key:")
                        Text("Either navigate with the arrow keys or number shortcuts,")
                        Text("then push action+enter, or action+mouse click")
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Picker("", selection: $s.actionModifierKey) {
                        Text("Command (⌘)").tag(1)
                        Text("Option (⌥)").tag(0)
                        Text("Control (⌃)").tag(2)
                        Text("Shift (⇧)").tag(3)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            Text("Action Menu")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                actionTreePane
                actionControlsPane
                    .frame(width: 120)
                actionCatalogPane
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .top)

            scriptEditorPane
                .frame(maxWidth: .infinity, minHeight: 180, idealHeight: 220)
        }
        .padding(4)
        .onAppear {
            ensureTreeSelection()
            _ = try? UserActionScriptsStore.ensureDirectory()
        }
        .onChange(of: rootNodes.count) { _, _ in
            ensureTreeSelection()
        }
        .onChange(of: rightTab) { _, tab in
            if tab == .users {
                _ = try? UserActionScriptsStore.ensureDirectory()
                catalogEpoch += 1
            }
        }
    }

    // MARK: - Helpers

    private var actionTreePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current actions")
                .font(.subheadline)
                .fontWeight(.medium)

            List {
                ForEach(flattenedTreeRows) { row in
                    actionFlatRow(row)
                        .listRowBackground(rowBackground(isSelected: selectedNodeToken == row.token))
                }
            }
            .listStyle(.sidebar)
            .dropDestination(for: String.self) { items, _ in
                guard let sourceToken = items.first,
                      let source = nodeForToken(sourceToken)
                else { return false }

                return moveNode(source, destinationParent: nil, destinationIndex: sortedRoots.count)
            }
        }
    }

    private struct TreeRow: Identifiable {
        var id: String { token }
        let token: String
        let node: ActionNode
        let depth: Int
        let hasChildren: Bool
    }

    private var flattenedTreeRows: [TreeRow] {
        var rows: [TreeRow] = []
        func walk(_ nodes: [ActionNode], depth: Int) {
            for node in nodes.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                let token = nodeToken(node)
                let children = node.children.sorted { $0.sortIndex < $1.sortIndex }
                let hasChildren = !node.isLeaf && !children.isEmpty
                rows.append(TreeRow(token: token, node: node, depth: depth, hasChildren: hasChildren))
                if hasChildren, expandedFolderTokens.contains(token) {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(sortedRoots, depth: 0)
        return rows
    }

    private func actionFlatRow(_ row: TreeRow) -> some View {
        let node = row.node
        return HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 14)

            if row.hasChildren {
                Image(systemName: expandedFolderTokens.contains(row.token) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleExpansion(row.token)
                    }
            } else {
                Color.clear.frame(width: 18, height: 18)
            }

            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { node.isEnabled },
                    set: { newValue in
                        node.isEnabled = newValue
                        persist()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                Image(systemName: node.isLeaf ? "bolt.fill" : "folder.fill")
                    .foregroundStyle(node.isLeaf ? .orange : .accentColor)

                actionTitleLabel(for: node)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectTreeNode(node)
            }
        }
        .draggable(row.token)
        .dropDestination(for: String.self) { items, _ in
            guard let sourceToken = items.first else { return false }
            return handleDrop(sourceToken: sourceToken, onto: node)
        }
    }

    private func toggleExpansion(_ token: String) {
        if expandedFolderTokens.contains(token) {
            expandedFolderTokens.remove(token)
        } else {
            expandedFolderTokens.insert(token)
        }
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.clear
    }

    private func selectTreeNode(_ node: ActionNode) {
        selectedNodeToken = nodeToken(node)
        if editingNodeID != nil, editingNodeID != node.persistentModelID {
            commitInlineRename()
        }
        presentScript(forActionNode: node)
    }

    private func selectCatalogNode(id: String) {
        selectedCatalogID = id
        if let item = catalogLeafItemsByID[id] {
            presentScript(forCatalogItem: item)
        } else {
            clearScriptEditor(placeholder: "Select a JavaScript action to view or edit its source.")
        }
    }

    private func presentScript(forCatalogItem item: AvailableActionItem) {
        guard item.actionType == "javaScript", let path = item.scriptPath else {
            clearScriptEditor(
                placeholder: item.actionType == "builtin"
                    ? "Built-in actions are implemented in Swift and have no JavaScript source."
                    : "Select a JavaScript action to view or edit its source."
            )
            return
        }
        presentScript(title: item.name, path: path)
    }

    private func presentScript(forActionNode node: ActionNode) {
        if let inline = node.scriptContent, !inline.isEmpty {
            scriptTitle = node.title
            scriptBody = inline
            scriptFileURL = nil
            scriptIsEditable = true
            scriptHasChanges = false
            scriptPlaceholder = nil
            scriptError = nil
            return
        }
        guard node.actionType == "javaScript", let path = node.scriptPath else {
            clearScriptEditor(placeholder: "Select a JavaScript action to view or edit its source.")
            return
        }
        presentScript(title: node.title, path: path)
    }

    private func presentScript(title: String, path: String) {
        let url = URL(fileURLWithPath: path)
        guard let contents = UserActionScriptsStore.load(at: url) else {
            clearScriptEditor(placeholder: "Could not read script at \(path)")
            return
        }
        scriptTitle = title
        scriptBody = contents
        scriptFileURL = url
        scriptIsEditable = UserActionScriptsStore.isUserScript(at: path)
        scriptHasChanges = false
        scriptPlaceholder = nil
        scriptError = nil
    }

    private func clearScriptEditor(placeholder: String) {
        scriptTitle = ""
        scriptBody = ""
        scriptFileURL = nil
        scriptIsEditable = false
        scriptHasChanges = false
        scriptPlaceholder = placeholder
        scriptError = nil
    }

    private func createNewUserScript() {
        do {
            let url = try UserActionScriptsStore.saveNewScript(
                preferredTitle: "Untitled Action",
                content: UserActionScriptsStore.defaultTemplate
            )
            rightTab = .users
            catalogEpoch += 1
            expandedCatalogFolderIDs = []
            selectedCatalogID = "script:\(url.path)"
            presentScript(title: UserActionScriptsStore.title(fromScriptURL: url), path: url.path)
            scriptHasChanges = false
        } catch {
            scriptError = error.localizedDescription
        }
    }

    private func duplicateCurrentAsUserTemplate() {
        let title = scriptTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = title.isEmpty ? "Custom Action" : title
        do {
            let url = try UserActionScriptsStore.saveNewScript(
                preferredTitle: preferred,
                content: scriptBody
            )
            rightTab = .users
            catalogEpoch += 1
            selectedCatalogID = "script:\(url.path)"
            presentScript(title: UserActionScriptsStore.title(fromScriptURL: url), path: url.path)
        } catch {
            scriptError = error.localizedDescription
        }
    }

    private func saveCurrentScript() {
        guard scriptIsEditable else { return }
        let trimmedTitle = scriptTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            scriptError = "Give the script a name before saving."
            return
        }

        do {
            try UserActionScriptsStore.ensureDirectory()
            let destination: URL
            if let existing = scriptFileURL, UserActionScriptsStore.isUserScript(at: existing.path) {
                let renamed = try UserActionScriptsStore.rename(at: existing, toPreferredTitle: trimmedTitle)
                try UserActionScriptsStore.save(at: renamed, content: scriptBody)
                updateActionNodesScriptPath(from: existing, to: renamed, title: trimmedTitle)
                destination = renamed
            } else {
                destination = try UserActionScriptsStore.saveNewScript(
                    preferredTitle: trimmedTitle,
                    content: scriptBody
                )
            }
            catalogEpoch += 1
            selectedCatalogID = "script:\(destination.path)"
            presentScript(title: UserActionScriptsStore.title(fromScriptURL: destination), path: destination.path)
            scriptError = nil
        } catch {
            scriptError = error.localizedDescription
        }
    }

    private func deleteCurrentUserScript() {
        guard let url = scriptFileURL, UserActionScriptsStore.isUserScript(at: url.path) else { return }
        do {
            try UserActionScriptsStore.delete(at: url)
            removeActionNodes(referencingScriptPath: url.path)
            catalogEpoch += 1
            selectedCatalogID = nil
            clearScriptEditor(placeholder: "Script deleted. Select another action or create a new script.")
        } catch {
            scriptError = error.localizedDescription
        }
    }

    private func revealUserScriptsFolder() {
        do {
            try UserActionScriptsStore.revealInFinder()
        } catch {
            scriptError = error.localizedDescription
        }
    }

    private func updateActionNodesScriptPath(from oldURL: URL, to newURL: URL, title: String) {
        let oldPath = oldURL.path
        for node in allNodes where node.scriptPath == oldPath {
            node.scriptPath = newURL.path
            if node.title == UserActionScriptsStore.title(fromScriptURL: oldURL) {
                node.title = title
            }
        }
        persist()
    }

    private func removeActionNodes(referencingScriptPath path: String) {
        let victims = allNodes.filter { $0.scriptPath == path }
        for node in victims {
            let parent = node.parent
            modelContext.delete(node)
            normalizeSiblings(in: parent)
        }
        if !victims.isEmpty {
            persist()
            ensureTreeSelection()
        }
    }

    private func ensureTreeSelection() {
        if let selectedNodeToken,
           allNodes.contains(where: { nodeToken($0) == selectedNodeToken }) {
            return
        }
        selectedNodeToken = sortedRoots.first.map(nodeToken)
    }

    @ViewBuilder
    private func actionTitleLabel(for node: ActionNode) -> some View {
        if editingNodeID == node.persistentModelID {
            TextField("Name", text: $editingTitle)
                .textFieldStyle(.plain)
                .focused($isInlineNameFocused)
                .onSubmit { commitInlineRename() }
                .onExitCommand { cancelInlineRename() }
                .onChange(of: isInlineNameFocused) { _, focused in
                    if !focused {
                        commitInlineRename()
                    }
                }
        } else {
            Text(node.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .help(node.title)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        beginInlineRename(node)
                    }
                )
        }
    }

    private func beginInlineRename(_ node: ActionNode) {
        selectTreeNode(node)
        editingNodeID = node.persistentModelID
        editingTitle = node.title
        DispatchQueue.main.async {
            isInlineNameFocused = true
        }
    }

    private func commitInlineRename() {
        guard let editingNodeID,
              let node = allNodes.first(where: { $0.persistentModelID == editingNodeID })
        else {
            cancelInlineRename()
            return
        }

        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != node.title {
            node.title = trimmed
            persist()
        }

        self.editingNodeID = nil
        isInlineNameFocused = false
    }

    private func cancelInlineRename() {
        editingNodeID = nil
        isInlineNameFocused = false
        editingTitle = ""
    }

    private var actionControlsPane: some View {
        VStack(spacing: 8) {
            Button {
                addSelectedCatalogAction()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(selectedCatalogItem == nil)

            Button {
                addFolder()
            } label: {
                Label("Folder", systemImage: "folder.badge.plus")
            }

            Button(role: .destructive) {
                removeSelectedNode()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedNode == nil)

            Divider()

            Button {
                moveSelectedNode(delta: -1)
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .disabled(!canMoveSelectedNode(delta: -1))

            Button {
                moveSelectedNode(delta: 1)
            } label: {
                Label("Down", systemImage: "arrow.down")
            }
            .disabled(!canMoveSelectedNode(delta: 1))
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .padding(.top, 28)
    }

    private var actionCatalogPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $rightTab) {
                ForEach(RightTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if rightTab == .users, flattenedCatalogRows.isEmpty {
                VStack(spacing: 10) {
                    ContentUnavailableView(
                        "No user scripts",
                        systemImage: "doc.badge.plus",
                        description: Text("Create one here, or open the JavaScript tab, select an action, and choose Copy to User’s.")
                    )
                    HStack(spacing: 8) {
                        Button("New Script") { createNewUserScript() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        compactIconButton(
                            systemImage: "folder",
                            help: "Reveal scripts folder",
                            action: revealUserScriptsFolder
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(flattenedCatalogRows) { row in
                        catalogFlatRow(row)
                            .listRowBackground(rowBackground(isSelected: selectedCatalogID == row.id))
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var scriptEditorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Script")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if scriptPlaceholder == nil {
                    TextField("Script name", text: $scriptTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .disabled(!scriptIsEditable)
                        .onChange(of: scriptTitle) { _, _ in
                            if scriptIsEditable { scriptHasChanges = true }
                        }

                    if scriptIsEditable {
                        Text(scriptHasChanges ? "Edited" : "Saved")
                            .font(.caption)
                            .foregroundStyle(scriptHasChanges ? .orange : .secondary)
                    } else {
                        Text("Read-only · bundled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if canDuplicateAsTemplate {
                    Button("Copy to User’s") { duplicateCurrentAsUserTemplate() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Create an editable copy under the User’s tab")
                }

                if scriptIsEditable {
                    Button("Save") { saveCurrentScript() }
                        .controlSize(.small)
                        .disabled(!scriptHasChanges || scriptBody.isEmpty)
                        .keyboardShortcut("s", modifiers: .command)

                    Button("New") { createNewUserScript() }
                        .controlSize(.small)

                    compactIconButton(
                        systemImage: "trash",
                        help: "Delete script",
                        role: .destructive,
                        disabled: scriptFileURL == nil,
                        action: deleteCurrentUserScript
                    )

                    compactIconButton(
                        systemImage: "folder",
                        help: "Reveal scripts folder",
                        action: revealUserScriptsFolder
                    )
                } else if rightTab == .users {
                    Button("New") { createNewUserScript() }
                        .controlSize(.small)

                    compactIconButton(
                        systemImage: "folder",
                        help: "Reveal scripts folder",
                        action: revealUserScriptsFolder
                    )
                }
            }

            if let scriptError {
                Text(scriptError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let scriptPlaceholder {
                Text(scriptPlaceholder)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                TextEditor(text: Binding(
                    get: { scriptBody },
                    set: { newValue in
                        guard scriptIsEditable else { return }
                        scriptBody = newValue
                        scriptHasChanges = true
                    }
                ))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .opacity(scriptIsEditable ? 1 : 0.92)
            }
        }
    }

    private var canDuplicateAsTemplate: Bool {
        guard scriptPlaceholder == nil, let url = scriptFileURL else { return false }
        return !UserActionScriptsStore.isUserScript(at: url.path)
    }

    private func compactIconButton(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(help)
        .disabled(disabled)
    }

    private struct CatalogRow: Identifiable {
        let id: String
        let node: CatalogNode
        let depth: Int
        let hasChildren: Bool
    }

    private var flattenedCatalogRows: [CatalogRow] {
        var rows: [CatalogRow] = []
        func walk(_ nodes: [CatalogNode], depth: Int) {
            for node in nodes {
                let children = node.visibleChildren ?? []
                let hasChildren = !node.isLeaf && !children.isEmpty
                rows.append(CatalogRow(id: node.id, node: node, depth: depth, hasChildren: hasChildren))
                if hasChildren, expandedCatalogFolderIDs.contains(node.id) {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(catalogNodes, depth: 0)
        return rows
    }

    private func catalogFlatRow(_ row: CatalogRow) -> some View {
        let node = row.node
        return HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 14)

            if row.hasChildren {
                Image(systemName: expandedCatalogFolderIDs.contains(row.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if expandedCatalogFolderIDs.contains(row.id) {
                            expandedCatalogFolderIDs.remove(row.id)
                        } else {
                            expandedCatalogFolderIDs.insert(row.id)
                        }
                    }
            } else {
                Color.clear.frame(width: 18, height: 18)
            }

            HStack(spacing: 6) {
                Image(systemName: node.isLeaf ? "bolt.fill" : "folder.fill")
                    .foregroundStyle(node.isLeaf ? .orange : .accentColor)
                Text(node.name)
                    .lineLimit(1)
                    .help(node.name)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .help(node.name)
            .onTapGesture(count: 2) {
                guard node.isLeaf else { return }
                selectCatalogNode(id: node.id)
                addSelectedCatalogAction()
            }
            .onTapGesture {
                selectCatalogNode(id: node.id)
            }
        }
    }

    private var sortedRoots: [ActionNode] {
        rootNodes.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var selectedNode: ActionNode? {
        guard let selectedNodeToken else { return nil }
        return allNodes.first { nodeToken($0) == selectedNodeToken }
    }

    private var allNodes: [ActionNode] {
        flatten(nodes: sortedRoots)
    }

    private var selectedCatalogItem: AvailableActionItem? {
        guard let selectedCatalogID else { return nil }
        return catalogLeafItemsByID[selectedCatalogID]
    }

    private var catalogLeafItemsByID: [String: AvailableActionItem] {
        var result: [String: AvailableActionItem] = [:]

        func collect(_ nodes: [CatalogNode]) {
            for node in nodes {
                if let item = node.item {
                    result[item.id] = item
                }
                if !node.children.isEmpty {
                    collect(node.children)
                }
            }
        }

        collect(catalogNodes)
        return result
    }

    private var catalogNodes: [CatalogNode] {
        _ = catalogEpoch
        switch rightTab {
        case .builtin:
            return [
                CatalogNode(
                    id: "builtin:pasteAsPlainText",
                    name: "Paste as Plain Text",
                    isLeaf: true,
                    item: AvailableActionItem(id: "builtin:pasteAsPlainText", name: "Paste as Plain Text", actionType: "builtin", actionName: "pasteAsPlainText"),
                    children: []
                ),
                CatalogNode(
                    id: "builtin:pasteAsFilePath",
                    name: "Paste as File Path",
                    isLeaf: true,
                    item: AvailableActionItem(id: "builtin:pasteAsFilePath", name: "Paste as File Path", actionType: "builtin", actionName: "pasteAsFilePath"),
                    children: []
                ),
                CatalogNode(
                    id: "builtin:pasteAsHFSFilePath",
                    name: "Paste as HFS File Path",
                    isLeaf: true,
                    item: AvailableActionItem(id: "builtin:pasteAsHFSFilePath", name: "Paste as HFS File Path", actionType: "builtin", actionName: "pasteAsHFSFilePath"),
                    children: []
                ),
                CatalogNode(
                    id: "builtin:removeAction",
                    name: "Remove",
                    isLeaf: true,
                    item: AvailableActionItem(id: "builtin:removeAction", name: "Remove", actionType: "builtin", actionName: "removeAction"),
                    children: []
                ),
            ]
        case .javaScript:
            let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("scripts/action")
            return scriptCatalogNodes(in: bundleURL)
        case .users:
            return scriptCatalogNodes(in: UserActionScriptsStore.directory)
        }
    }

    private func scriptCatalogNodes(in root: URL?) -> [CatalogNode] {
        guard let root else { return [] }

        struct ScriptRecord {
            let relativePath: String
            let fullPath: String
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [ScriptRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "js" else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            records.append(ScriptRecord(relativePath: relative, fullPath: url.path))
        }

        final class MutableNode {
            let id: String
            let name: String
            var isLeaf: Bool
            var item: AvailableActionItem?
            var children: [String: MutableNode] = [:]

            init(id: String, name: String, isLeaf: Bool, item: AvailableActionItem? = nil) {
                self.id = id
                self.name = name
                self.isLeaf = isLeaf
                self.item = item
            }
        }

        let rootNode = MutableNode(id: "root", name: "root", isLeaf: false)

        for record in records {
            let parts = record.relativePath.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }

            var cursor = rootNode
            for (idx, part) in parts.enumerated() {
                let isLast = idx == parts.count - 1
                if isLast {
                    let name = part.replacingOccurrences(of: ".js", with: "")
                    let item = AvailableActionItem(
                        id: "script:\(record.fullPath)",
                        name: name,
                        actionType: "javaScript",
                        actionName: nil,
                        scriptPath: record.fullPath
                    )
                    cursor.children[name] = MutableNode(
                        id: item.id,
                        name: name,
                        isLeaf: true,
                        item: item
                    )
                } else {
                    if cursor.children[part] == nil {
                        cursor.children[part] = MutableNode(
                            id: "folder:\(parts.prefix(idx + 1).joined(separator: "/"))",
                            name: part,
                            isLeaf: false
                        )
                    }
                    if let next = cursor.children[part] {
                        cursor = next
                    }
                }
            }
        }

        func freeze(_ node: MutableNode) -> CatalogNode {
            let sortedChildren = node.children.values
                .sorted { lhs, rhs in
                    if lhs.isLeaf != rhs.isLeaf {
                        return lhs.isLeaf && !rhs.isLeaf ? false : true
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .map(freeze)

            return CatalogNode(
                id: node.id,
                name: node.name,
                isLeaf: node.isLeaf,
                item: node.item,
                children: sortedChildren
            )
        }

        return rootNode.children.values
            .sorted { lhs, rhs in
                if lhs.isLeaf != rhs.isLeaf {
                    return lhs.isLeaf && !rhs.isLeaf ? false : true
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map(freeze)
    }

    private func addSelectedCatalogAction() {
        guard let item = selectedCatalogItem else { return }
        let newNode = ActionNode(title: item.name, isLeaf: true, sortIndex: 0)
        newNode.actionType = item.actionType
        newNode.actionName = item.actionName
        newNode.scriptPath = item.scriptPath
        insert(node: newNode, into: selectedFolderTarget)
        selectedNodeToken = nodeToken(newNode)
        if let folder = selectedFolderTarget {
            expandedFolderTokens.insert(nodeToken(folder))
        }
    }

    private func addFolder() {
        let newFolder = ActionNode(title: "New Folder", isLeaf: false, sortIndex: 0)
        insert(node: newFolder, into: selectedFolderTarget)
        selectedNodeToken = nodeToken(newFolder)
        if let folder = selectedFolderTarget {
            expandedFolderTokens.insert(nodeToken(folder))
        }
        beginInlineRename(newFolder)
    }

    private var selectedFolderTarget: ActionNode? {
        guard let selectedNode else { return nil }
        return selectedNode.isLeaf ? selectedNode.parent : selectedNode
    }

    private func insert(node: ActionNode, into folder: ActionNode?) {
        if let folder {
            node.parent = folder
            node.sortIndex = nextSortIndex(in: folder)
            folder.children.append(node)
        } else {
            node.parent = nil
            node.sortIndex = nextRootSortIndex()
        }

        modelContext.insert(node)
        persist()
    }

    private func removeSelectedNode() {
        guard let selectedNode else { return }
        let parent = selectedNode.parent
        let removedToken = nodeToken(selectedNode)
        let selectedID = selectedNode.persistentModelID

        if editingNodeID == selectedID {
            cancelInlineRename()
        }

        modelContext.delete(selectedNode)
        normalizeSiblings(in: parent)
        persist()

        if selectedNodeToken == removedToken {
            if let parent {
                selectedNodeToken = nodeToken(parent)
            } else {
                selectedNodeToken = sortedRoots.first.map(nodeToken)
            }
        }
    }

    private func canMoveSelectedNode(delta: Int) -> Bool {
        guard let selectedNode else { return false }
        let siblings = siblingsOfSelectedNode(selectedNode)
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == selectedNode.persistentModelID }) else {
            return false
        }
        let newIndex = index + delta
        return newIndex >= 0 && newIndex < siblings.count
    }

    private func moveSelectedNode(delta: Int) {
        guard let selectedNode else { return }
        let siblings = siblingsOfSelectedNode(selectedNode)
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == selectedNode.persistentModelID }) else {
            return
        }
        let newIndex = index + delta
        guard newIndex >= 0 && newIndex < siblings.count else { return }

        let other = siblings[newIndex]
        let currentSort = selectedNode.sortIndex
        selectedNode.sortIndex = other.sortIndex
        other.sortIndex = currentSort
        normalizeSiblings(in: selectedNode.parent)
        persist()
    }

    private func siblingsOfSelectedNode(_ node: ActionNode) -> [ActionNode] {
        if let parent = node.parent {
            return parent.children.sorted { $0.sortIndex < $1.sortIndex }
        }
        return sortedRoots
    }

    private func nextRootSortIndex() -> Int {
        (sortedRoots.last?.sortIndex ?? -1) + 1
    }

    private func nextSortIndex(in folder: ActionNode) -> Int {
        let sorted = folder.children.sorted { $0.sortIndex < $1.sortIndex }
        return (sorted.last?.sortIndex ?? -1) + 1
    }

    private func normalizeSiblings(in parent: ActionNode?) {
        if let parent {
            let siblings = parent.children.sorted { $0.sortIndex < $1.sortIndex }
            for (idx, node) in siblings.enumerated() {
                node.sortIndex = idx
            }
            return
        }

        let roots = sortedRoots
        for (idx, node) in roots.enumerated() {
            node.sortIndex = idx
        }
    }

    private func flatten(nodes: [ActionNode]) -> [ActionNode] {
        var result: [ActionNode] = []
        for node in nodes.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            result.append(node)
            result.append(contentsOf: flatten(nodes: node.children))
        }
        return result
    }

    private func persist() {
        try? modelContext.save()
    }

    // MARK: - Drag and Drop

    private func nodeToken(_ node: ActionNode) -> String {
        String(describing: node.persistentModelID)
    }

    private func nodeForToken(_ token: String) -> ActionNode? {
        allNodes.first { nodeToken($0) == token }
    }

    private func handleDrop(sourceToken: String, onto target: ActionNode) -> Bool {
        guard let source = nodeForToken(sourceToken), source !== target else { return false }

        if target.isLeaf {
            let parent = target.parent
            let siblings = parent == nil
                ? sortedRoots
                : parent!.children.sorted { $0.sortIndex < $1.sortIndex }
            guard let targetIndex = siblings.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else {
                return false
            }
            return moveNode(source, destinationParent: parent, destinationIndex: targetIndex + 1)
        }

        let children = target.children.sorted { $0.sortIndex < $1.sortIndex }
        return moveNode(source, destinationParent: target, destinationIndex: children.count)
    }

    private func moveNode(_ source: ActionNode, destinationParent: ActionNode?, destinationIndex: Int) -> Bool {
        if let destinationParent {
            if source === destinationParent || isDescendant(destinationParent, of: source) {
                return false
            }
        }

        let sourceParent = source.parent
        if sourceParent === destinationParent {
            if sourceParent == nil {
                var roots = sortedRoots.filter { $0.persistentModelID != source.persistentModelID }
                let insertionIndex = max(0, min(destinationIndex, roots.count))
                roots.insert(source, at: insertionIndex)
                renumber(nodes: roots)
                persist()
                return true
            }

            guard let sourceParent else { return false }
            var siblings = sourceParent.children
                .filter { $0.persistentModelID != source.persistentModelID }
                .sorted { $0.sortIndex < $1.sortIndex }
            let insertionIndex = max(0, min(destinationIndex, siblings.count))
            siblings.insert(source, at: insertionIndex)
            sourceParent.children = siblings
            renumber(nodes: siblings)
            persist()
            return true
        }

        if let sourceParent {
            sourceParent.children.removeAll { $0.persistentModelID == source.persistentModelID }
            renumber(nodes: sourceParent.children.sorted { $0.sortIndex < $1.sortIndex })
        }

        if let destinationParent {
            var children = destinationParent.children
                .filter { $0.persistentModelID != source.persistentModelID }
                .sorted { $0.sortIndex < $1.sortIndex }
            let insertionIndex = max(0, min(destinationIndex, children.count))
            source.parent = destinationParent
            children.insert(source, at: insertionIndex)
            destinationParent.children = children
            renumber(nodes: children)
        } else {
            source.parent = nil
            var roots = sortedRoots.filter { $0.persistentModelID != source.persistentModelID }
            let insertionIndex = max(0, min(destinationIndex, roots.count))
            roots.insert(source, at: insertionIndex)
            renumber(nodes: roots)
        }

        selectedNodeToken = nodeToken(source)
        persist()
        return true
    }

    private func renumber(nodes: [ActionNode]) {
        for (index, node) in nodes.enumerated() {
            node.sortIndex = index
        }
    }

    private func isDescendant(_ candidate: ActionNode, of ancestor: ActionNode) -> Bool {
        var current = candidate.parent
        while let node = current {
            if node === ancestor { return true }
            current = node.parent
        }
        return false
    }
}

// MARK: - Preview

#Preview {
    ActionsPrefsView()
        .environment(ClipMenuSettings())
    .modelContainer(for: [ActionNode.self], inMemory: true)
    .frame(width: 820, height: 620)
}
