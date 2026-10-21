import SwiftUI

/// Renders the action tree as a menu, respecting folder nesting.
///
/// Mirrors `legacy/Source/MenuController.m` action menu construction and
/// `legacy/Source/ActionController.m` availability filtering.
struct ActionSection: View {

    /// Flat root-level nodes (service fetches and passes these in).
    let nodes: [ActionNode]
    /// The clip on which the selected action will operate.
    let target: ClipEntry

    @Environment(\.actionService) private var actionService
    @Environment(\.clipsService) private var clipsService

    var body: some View {
        ForEach(nodes.sorted { $0.sortIndex < $1.sortIndex }) { node in
            if node.isLeaf {
                if node.isEnabled {
                    Button(node.title) { performAction(node) }
                }
            } else {
                let children = node.children
                    .filter(\.isEnabled)
                    .sorted { $0.sortIndex < $1.sortIndex }
                if !children.isEmpty {
                    Menu(node.title) {
                        ForEach(children) { child in
                            if child.isLeaf {
                                Button(child.title) { performAction(child) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func performAction(_ node: ActionNode) {
        Task {
            await actionService.perform(action: node, on: target, executionContext: .pasteContext)
        }
    }
}

// MARK: - Preview

#Preview {
    let leaf = ActionNode(title: "Paste as Plain Text", isLeaf: true, sortIndex: 0)
    leaf.actionType = "builtin"
    leaf.actionName = "pasteAsPlainText"

    let folder = ActionNode(title: "Case", isLeaf: false, sortIndex: 1)
    let upper = ActionNode(title: "Uppercase", isLeaf: true, sortIndex: 0)
    upper.actionType = "javaScript"
    folder.children = [upper]

    let entry = ClipEntry()
    entry.stringValue = "hello"
    entry.types = ["NSStringPboardType"]

    return ActionSection(nodes: [leaf, folder], target: entry)
        .environment(\.actionService, ActionService())
        .environment(\.clipsService, ClipsService(settings: ClipMenuSettings()))
        .padding()
}
