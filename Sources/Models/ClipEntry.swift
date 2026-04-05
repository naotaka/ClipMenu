import SwiftData
import Foundation

/// A single clipboard entry captured from NSPasteboard.
///
/// Equality / deduplication uses `contentHash` which replicates the algorithm
/// from `legacy/Source/Clip.m -hash`.  See that file for the exact XOR
/// sequence before changing this implementation.
@Model
final class ClipEntry {

    var createdAt: Date
    var lastUsedAt: Date

    /// Pasteboard type strings in the order they appeared on the pasteboard.
    var types: [String]

    var stringValue: String?
    /// RTF or RTFD bytes (see `isRTFD` to distinguish).
    var rtfData: Data?
    /// `true` when `rtfData` contains an RTFD document (file-wrapper RTF).
    var isRTFD: Bool
    var pdfData: Data?
    var filenames: [String]?
    var urlStrings: [String]?
    /// TIFF bytes.
    var imageData: Data?

    init() {
        createdAt  = .now
        lastUsedAt = .now
        types      = []
        isRTFD     = false
    }

    var contentHash: Int {
        // Use NSString.hash (stable across process runs) rather than Swift's
        // randomised hashValue so that deduplication survives app restarts.
        // This mirrors legacy/Source/Clip.m which calls -hash on NSString.
        var h = (types.joined() as NSString).hash

        if let imageData {
            h ^= imageData.count
        }

        if let filenames {
            for filename in filenames {
                h ^= (filename as NSString).hash
            }
        } else if let urlStrings {
            for urlString in urlStrings {
                h ^= (urlString as NSString).hash
            }
        } else if let pdfData {
            h ^= pdfData.count
        } else if let stringValue {
            h ^= (stringValue as NSString).hash
        }

        h ^= (rtfData?.count ?? 0)
        return h
    }
}
