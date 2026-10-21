import AppKit
import Foundation
import ObjectiveC

/// Case- and diacritic-insensitive contiguous substring match (not fuzzy / not skipping characters).
enum MenuFilterSubstring {
    static func matches(_ query: String, in haystack: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return haystack.localizedStandardContains(q)
    }
}

private var clipMenuFilterHaystackKey: UInt8 = 0

extension NSMenuItem {
    /// When set, this row is included in clip/snippet menu filtering.
    var clipMenuFilterHaystack: String? {
        get { objc_getAssociatedObject(self, &clipMenuFilterHaystackKey) as? String }
        set { objc_setAssociatedObject(self, &clipMenuFilterHaystackKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
}
