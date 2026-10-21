import AppKit
import Foundation

extension ActionOverlayItem {
    static func from(nodes: [ActionNode]) -> [ActionOverlayItem] {
        nodes
            .filter(\.isEnabled)
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { node in
                ActionOverlayItem(
                    id: String(describing: ObjectIdentifier(node)),
                    title: node.title,
                    isLeaf: node.isLeaf,
                    children: from(nodes: Array(node.children))
                )
            }
    }
}

extension ActionOverlayPresenter {
    func show(
        roots: [ActionNode],
        at screenPoint: NSPoint,
        replacing parentMenu: NSMenu? = nil,
        attachedTo item: NSMenuItem? = nil,
        onPick: @escaping (ActionNode) -> Void
    ) {
        let items = ActionOverlayItem.from(nodes: roots)
        var nodeByID: [String: ActionNode] = [:]
        func index(_ nodes: [ActionNode]) {
            for node in nodes {
                nodeByID[String(describing: ObjectIdentifier(node))] = node
                index(Array(node.children))
            }
        }
        index(roots)
        show(items: items, at: screenPoint, replacing: parentMenu, attachedTo: item) { item in
            if let node = nodeByID[item.id] {
                onPick(node)
            }
        }
    }
}
