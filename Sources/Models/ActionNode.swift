import SwiftData

/// A node in the action tree (folder or leaf action).
///
/// Mirrors the data shape in `legacy/Source/ActionNode.{h,m}`.
/// See those files and `legacy/Source/ActionNodeFactory.m` before
/// modifying the tree structure.
@Model
final class ActionNode {

    var title: String
    var isLeaf: Bool
    var isEnabled: Bool
    var sortIndex: Int

    /// `nil` for folder nodes; populated for leaf action nodes.
    var actionType: String?
    var actionName: String?
    var scriptPath: String?
    var scriptContent: String?

    @Relationship(deleteRule: .cascade)
    var children: [ActionNode] = []

    var parent: ActionNode?

    init(title: String, isLeaf: Bool = false, sortIndex: Int = 0) {
        self.title     = title
        self.isLeaf    = isLeaf
        self.isEnabled = true
        self.sortIndex = sortIndex
    }
}
