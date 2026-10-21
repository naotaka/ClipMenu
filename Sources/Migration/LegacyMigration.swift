import SwiftData
import Foundation
import CoreData

/// One-time import of `Snippets.xml` from the original ClipMenu app.
///
/// Completion is recorded in UserDefaults under `legacyMigrationCompleted`.
/// Clip history and actions are not read from the old archive or plist.
struct LegacyMigration {

    static let completedKey = "legacyMigrationCompleted"
    static let maximumXMLBytes = 16_777_216

    enum ImportFailure: Error {
        /// macOS refused to read the file, usually Desktop or Downloads privacy.
        case unreadable
        case invalid
    }

    static var isNeeded: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Call from AppDelegate.applicationDidFinishLaunching if `isNeeded`.
    static func run(in context: ModelContext) {
        if let snippetsURL = ClipStoreLocation.snippetsURL {
            _ = try? importSnippets(from: snippetsURL, into: context)
        }
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    // MARK: - Snippets (Core Data XML → SwiftData)

    /// Imports a ClipMenu `Snippets.xml` file. Folders are matched by title.
    /// A snippet that already has the same title and text in that folder is skipped.
    static func importSnippets(from url: URL, into context: ModelContext) throws -> SnippetXMLImportResult {
        // The original ClipMenu store and a clip'M export do not share a Core Data
        // model hash (16-bit indexes and a required folder relationship, versus
        // 32-bit indexes). XML stores cannot migrate, so read the elements directly.
        let data = try validatedSnippetXML(at: url)
        let legacyFolders = try LegacySnippetDocument.folders(in: data)

        let existingFolders = (try? context.fetch(FetchDescriptor<SnippetFolder>())) ?? []
        var foldersByTitle: [String: SnippetFolder] = [:]
        for folder in existingFolders where foldersByTitle[folder.title] == nil {
            foldersByTitle[folder.title] = folder
        }
        var nextFolderIndex = (existingFolders.map(\.sortIndex).max() ?? -1) + 1
        var result = SnippetXMLImportResult()

        for legacyFolder in legacyFolders {
            let folder: SnippetFolder
            if let existing = foldersByTitle[legacyFolder.title] {
                folder = existing
            } else {
                let created = SnippetFolder(title: legacyFolder.title, sortIndex: nextFolderIndex)
                created.isEnabled = legacyFolder.isEnabled
                context.insert(created)
                foldersByTitle[legacyFolder.title] = created
                folder = created
                nextFolderIndex += 1
                result.foldersAdded += 1
            }

            var seen = Set(folder.snippets.map { snippetKey(title: $0.title, content: $0.content) })
            var nextSnippetIndex = (folder.snippets.map(\.sortIndex).max() ?? -1) + 1
            for legacySnippet in legacyFolder.snippets.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                let key = snippetKey(title: legacySnippet.title, content: legacySnippet.content)
                if seen.contains(key) {
                    result.snippetsSkipped += 1
                    continue
                }
                let snippet = Snippet(title: legacySnippet.title, content: legacySnippet.content, sortIndex: nextSnippetIndex)
                snippet.isEnabled = legacySnippet.isEnabled
                snippet.folder = folder
                folder.snippets.append(snippet)
                context.insert(snippet)
                seen.insert(key)
                nextSnippetIndex += 1
                result.snippetsAdded += 1
            }
        }

        do {
            try context.save()
        } catch {
            throw ImportFailure.invalid
        }
        return result
    }

    /// Writes the current snippet library as a ClipMenu `Snippets.xml` file.
    static func exportSnippets(to url: URL, from context: ModelContext) throws {
        let model = makeLegacySnippetModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        // Build the entire export in a private replacement directory. Publishing
        // it atomically preserves an existing export if encoding or saving fails.
        let replacementDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true
        )
        defer { try? FileManager.default.removeItem(at: replacementDirectory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacementDirectory.path)
        let stagedURL = replacementDirectory.appendingPathComponent("Snippets.xml")
        let store = try coordinator.addPersistentStore(ofType: NSXMLStoreType, configurationName: nil, at: stagedURL, options: nil)
        let exportContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        exportContext.persistentStoreCoordinator = coordinator

        let folders = try context.fetch(FetchDescriptor<SnippetFolder>(sortBy: [SortDescriptor(\.sortIndex)]))
        for folder in folders {
            let folderObject = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: exportContext)
            folderObject.setValue(folder.title, forKey: "title")
            folderObject.setValue(folder.sortIndex, forKey: "index")
            folderObject.setValue(folder.isEnabled, forKey: "enabled")

            var snippetObjects: [NSManagedObject] = []
            for snippet in folder.snippets.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                let snippetObject = NSEntityDescription.insertNewObject(forEntityName: "Snippet", into: exportContext)
                snippetObject.setValue(snippet.title, forKey: "title")
                snippetObject.setValue(snippet.content, forKey: "content")
                snippetObject.setValue(snippet.sortIndex, forKey: "index")
                snippetObject.setValue(snippet.isEnabled, forKey: "enabled")
                snippetObject.setValue(folderObject, forKey: "folder")
                snippetObjects.append(snippetObject)
            }
            folderObject.setValue(NSSet(array: snippetObjects), forKey: "snippets")
        }
        try exportContext.save()
        try coordinator.remove(store)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagedURL.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: stagedURL, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: stagedURL, to: url)
        }
    }

    private static func validatedSnippetXML(at url: URL) throws -> Data {
        guard url.isFileURL else { throw ImportFailure.invalid }
        let data: Data
        do {
            // Data(contentsOf:) is what triggers the Desktop and Downloads
            // privacy prompt. A FileHandle read can fail before that prompt.
            data = try Data(contentsOf: url)
        } catch {
            throw ImportFailure.unreadable
        }
        guard data.count <= maximumXMLBytes,
              let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw ImportFailure.invalid
        }
        // Core Data's exporter adds this fixed DTD. Strip that one declaration
        // from the prolog. Snippet text may itself mention a DOCTYPE, so the
        // rest of the document is left unchanged. Any other DTD or entity in
        // the prolog is rejected.
        guard let root = text.range(of: "<database") else { throw ImportFailure.invalid }
        var prolog = String(text[..<root.lowerBound])
        let coreDataDTD = "<!DOCTYPE database SYSTEM \"file:///System/Library/DTDs/CoreData.dtd\">"
        if let allowed = prolog.range(of: coreDataDTD) {
            prolog.removeSubrange(allowed)
        }
        guard !prolog.contains("<!DOCTYPE"), !prolog.contains("<!ENTITY") else {
            throw ImportFailure.invalid
        }
        let sanitized = prolog + text[root.lowerBound...]
        let sanitizedData = Data(sanitized.utf8)
        let parser = XMLParser(data: sanitizedData)
        parser.shouldResolveExternalEntities = false
        let limits = SnippetXMLLimits()
        parser.delegate = limits
        guard parser.parse(), limits.isValid else { throw ImportFailure.invalid }
        return sanitizedData
    }

    private static func snippetKey(title: String, content: String) -> String {
        title + "\u{0}" + content
    }

    /// Constructs the legacy Snippets Core Data model programmatically.
    ///
    /// Avoids any dependency on a compiled `.mom`/`.momd` bundle resource.
    /// Matches the schema defined in `legacy/Snippets.xcdatamodel`.
    private static func makeLegacySnippetModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let folderEntity = NSEntityDescription()
        folderEntity.name = "Folder"
        folderEntity.managedObjectClassName = "NSManagedObject"

        let snippetEntity = NSEntityDescription()
        snippetEntity.name = "Snippet"
        snippetEntity.managedObjectClassName = "NSManagedObject"

        func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = true
            return a
        }

        folderEntity.properties = [
            attr("title", .stringAttributeType),
            attr("index", .integer32AttributeType),
            attr("enabled", .booleanAttributeType),
        ]
        snippetEntity.properties = [
            attr("title", .stringAttributeType),
            attr("content", .stringAttributeType),
            attr("index", .integer32AttributeType),
            attr("enabled", .booleanAttributeType),
        ]

        // Relationship: Folder.snippets ↔ Snippet.folder
        let folderSnippets = NSRelationshipDescription()
        folderSnippets.name = "snippets"
        folderSnippets.isOptional = true
        folderSnippets.minCount = 0
        folderSnippets.maxCount = 0  // to-many
        folderSnippets.destinationEntity = snippetEntity

        let snippetFolder = NSRelationshipDescription()
        snippetFolder.name = "folder"
        snippetFolder.isOptional = true
        snippetFolder.minCount = 0
        snippetFolder.maxCount = 1   // to-one
        snippetFolder.destinationEntity = folderEntity

        folderSnippets.inverseRelationship = snippetFolder
        snippetFolder.inverseRelationship = folderSnippets

        folderEntity.properties += [folderSnippets]
        snippetEntity.properties += [snippetFolder]

        model.entities = [folderEntity, snippetEntity]
        return model
    }
}

/// Reads ClipMenu's Core Data XML without opening it as a store. The original
/// app wrote 16-bit indexes and a required folder relationship; clip'M exports
/// 32-bit indexes. Those files do not open under one managed object model.
private enum LegacySnippetDocument {
    struct Folder {
        var title: String
        var sortIndex: Int
        var isEnabled: Bool
        var snippets: [Snippet]
    }

    struct Snippet {
        var title: String
        var content: String
        var sortIndex: Int
        var isEnabled: Bool
    }

    static func folders(in data: Data) throws -> [Folder] {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let builder = Builder()
        parser.delegate = builder
        guard parser.parse(), builder.sawDatabase, builder.rejectedObjects == 0 else {
            throw LegacyMigration.ImportFailure.invalid
        }
        return builder.assembledFolders()
    }

    private struct RawFolder {
        var title: String
        var sortIndex: Int
        var isEnabled: Bool
        var snippetIDs: [String]
    }

    private struct RawSnippet {
        var title: String
        var content: String
        var sortIndex: Int
        var isEnabled: Bool
        var folderID: String?
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var sawDatabase = false
        var rejectedObjects = 0
        private var folders: [String: RawFolder] = [:]
        private var snippets: [String: RawSnippet] = [:]
        private var kind: String?
        private var objectID = ""
        private var attribute: String?
        private var text = ""
        private var title = ""
        private var content = ""
        private var sortIndex = 0
        private var isEnabled = true
        private var folderID: String?
        private var snippetIDs: [String] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "database":
                sawDatabase = true
            case "object":
                kind = attributeDict["type"]?.uppercased()
                if kind != "FOLDER", kind != "SNIPPET" { rejectedObjects += 1 }
                objectID = attributeDict["id"] ?? ""
                title = ""
                content = ""
                sortIndex = 0
                isEnabled = true
                folderID = nil
                snippetIDs = []
            case "attribute":
                attribute = attributeDict["name"]
                text = ""
            case "relationship":
                let refs = attributeDict["idrefs"]?
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init) ?? []
                if attributeDict["name"] == "snippets" {
                    snippetIDs.append(contentsOf: refs)
                } else if attributeDict["name"] == "folder" {
                    folderID = refs.first
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if attribute != nil { text += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if attribute != nil, let string = String(data: CDATABlock, encoding: .utf8) {
                text += string
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "attribute":
                switch attribute {
                case "title": title = decodeCoreDataString(text)
                case "content": content = decodeCoreDataString(text)
                case "index":
                    sortIndex = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                case "enabled":
                    let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    isEnabled = token != "0" && token != "false" && token != "no"
                default:
                    break
                }
                attribute = nil
                text = ""
            case "object":
                switch kind {
                case "FOLDER":
                    folders[objectID] = RawFolder(title: title, sortIndex: sortIndex, isEnabled: isEnabled, snippetIDs: snippetIDs)
                case "SNIPPET":
                    snippets[objectID] = RawSnippet(title: title, content: content, sortIndex: sortIndex, isEnabled: isEnabled, folderID: folderID)
                default:
                    break
                }
                kind = nil
            default:
                break
            }
        }

        /// Core Data writes special characters as `\u` plus four hex digits, in
        /// little-endian UTF-16 order. `\u2600` is `&`, `\u3c00` is `<`.
        private func decodeCoreDataString(_ raw: String) -> String {
            var units: [UInt16] = []
            var decoded = ""
            func flushUnits() {
                guard !units.isEmpty else { return }
                decoded += String(decoding: units, as: UTF16.self)
                units.removeAll(keepingCapacity: true)
            }
            var index = raw.startIndex
            while index < raw.endIndex {
                if raw[index] == "\\",
                   let hexEnd = raw.index(index, offsetBy: 6, limitedBy: raw.endIndex),
                   raw[raw.index(after: index)] == "u" {
                    let hexStart = raw.index(index, offsetBy: 2)
                    if let value = UInt16(raw[hexStart..<hexEnd], radix: 16) {
                        units.append(value.byteSwapped)
                        index = hexEnd
                        continue
                    }
                }
                flushUnits()
                decoded.append(raw[index])
                index = raw.index(after: index)
            }
            flushUnits()
            return decoded
        }

        func assembledFolders() -> [Folder] {
            var snippetsByFolder: [String: [Snippet]] = [:]
            for (id, snippet) in snippets {
                let owner = snippet.folderID ?? folders
                    .filter { $0.value.snippetIDs.contains(id) }
                    .min { $0.value.sortIndex < $1.value.sortIndex }?
                    .key
                guard let owner, folders[owner] != nil else { continue }
                snippetsByFolder[owner, default: []].append(
                    Snippet(title: snippet.title, content: snippet.content, sortIndex: snippet.sortIndex, isEnabled: snippet.isEnabled)
                )
            }
            return folders
                .sorted { lhs, rhs in
                    if lhs.value.sortIndex != rhs.value.sortIndex { return lhs.value.sortIndex < rhs.value.sortIndex }
                    return lhs.key < rhs.key
                }
                .map { id, folder in
                    Folder(title: folder.title, sortIndex: folder.sortIndex, isEnabled: folder.isEnabled,
                           snippets: snippetsByFolder[id] ?? [])
                }
        }
    }
}

struct SnippetXMLImportResult {
    var foldersAdded = 0
    var snippetsAdded = 0
    var snippetsSkipped = 0
}

/// Reject pathological nesting/object counts before passing the snapshot to Core Data.
private final class SnippetXMLLimits: NSObject, XMLParserDelegate {
    private var depth = 0
    private var elements = 0
    private(set) var isValid = true

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        depth += 1
        elements += 1
        if depth > 32 || elements > 100_000 {
            isValid = false
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1
    }
}
