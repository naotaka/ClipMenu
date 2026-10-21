import AppKit
import SwiftData

// Keep every script and migration fixture isolated from real application data.
enum ClipStoreLocation {
    static let userActionScriptsURL: URL? = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipMenu.ScriptSecurity.\(UUID().uuidString)/action", isDirectory: true)
    static let snippetsURL: URL? = nil
}

@main
enum ScriptSecuritySmoke {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ description: String) {
            guard condition else {
                fputs("[SCRIPT SECURITY] FAIL: \(description)\n", stderr)
                exit(1)
            }
            checks += 1
        }
        let directory = UserActionScriptsStore.directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try "var libraryValue = 'loaded';".write(to: library.appendingPathComponent("valid.js"), atomically: true, encoding: .utf8)
        let outside = directory.appendingPathComponent("outside.js")
        try "var libraryValue = 'outside';".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("escape.js"), withDestinationURL: outside)
        let engine = ScriptEngine(libraryRoots: [library])
        let clip = ScriptableClip(text: "private fixture")
        check(engine.run(script: "globalThis.secret = clipText; String.prototype.marker = 'poison'; return clipText;", clip: clip) == "private fixture", "valid transformation")
        check(engine.run(script: "return typeof secret + ':' + typeof ''.marker;", clip: ScriptableClip(text: "next")) == "undefined:undefined", "clipboard and prototype state leak across actions")
        check(engine.run(script: "ClipMenu.require('valid'); return libraryValue;", clip: clip) == "loaded", "normal library loading")
        check(engine.run(script: "return typeof libraryValue;", clip: clip) == "undefined", "library globals leak across actions")
        check(engine.run(script: "return ClipMenu.require('../outside.js');", clip: clip) == "false", "relative library traversal")
        check(engine.run(script: "return ClipMenu.require('escape.js');", clip: clip) == "false", "symlink library traversal")
        check(engine.run(script: "return ClipMenu.require(\(outside.path.debugDescription));", clip: clip) == "false", "absolute library traversal")
        check(engine.run(script: "return clipText;", clip: ScriptableClip(text: "'); throw new Error('injection'); //")) == "'); throw new Error('injection'); //", "clipboard source injection")
        check(engine.run(script: "return {toString() {throw new Error(clipText)}};", clip: clip) == nil, "throw during result coercion")
        check(engine.run(script: String(repeating: " ", count: ScriptEngine.maximumSourceBytes + 1), clip: clip) == nil, "oversized action source")
        let largeFile = library.appendingPathComponent("large.js")
        try Data(repeating: 32, count: ScriptEngine.maximumSourceBytes + 1).write(to: largeFile)
        check(ScriptFileAccess.readSource(at: largeFile) == nil, "oversized source file")
        check(ScriptFileAccess.readSource(at: library) == nil, "directory read as script")

        let valid = try UserActionScriptsStore.saveNewScript(preferredTitle: "Normal", content: "return clipText;")
        check(UserActionScriptsStore.isUserScript(at: valid.path), "user script classification")
        check(!UserActionScriptsStore.isUserScript(at: UserActionScriptsStore.directory.path), "actions root classified as editable script")
        let linkedDirectory = UserActionScriptsStore.directory.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: directory)
        let escaped = linkedDirectory.appendingPathComponent("outside.js")
        check(!UserActionScriptsStore.isUserScript(at: escaped.path), "symlinked folder permits external mutation")
        do {
            try UserActionScriptsStore.delete(at: escaped)
            check(false, "external script deleted")
        } catch { check(FileManager.default.fileExists(atPath: outside.path), "outside file preserved") }
        do {
            try UserActionScriptsStore.delete(at: UserActionScriptsStore.directory)
            check(false, "actions root deleted")
        } catch { check(FileManager.default.fileExists(atPath: valid.path), "root and scripts preserved") }
        let fakeBundle = directory.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: fakeBundle.appendingPathComponent("scripts/action"), withIntermediateDirectories: true)
        try "return 'bundled';".write(to: fakeBundle.appendingPathComponent("scripts/action/test.js"), atomically: true, encoding: .utf8)
        check(ActionService.scriptSource(inline: nil, path: "test.js", resourceRoot: fakeBundle) == "return 'bundled';", "bundled action loading")
        check(ActionService.scriptSource(inline: nil, path: "../../../outside.js", resourceRoot: fakeBundle) == nil, "bundled action traversal")
        check(ActionService.scriptSource(inline: nil, path: outside.path, resourceRoot: fakeBundle) != nil, "explicit user script path remains supported")

        let schema = Schema([Snippet.self, SnippetFolder.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let folder = SnippetFolder(title: "Security fixture")
        let snippet = Snippet(title: "Example", content: "Private & <literal> fixture")
        snippet.folder = folder
        folder.snippets.append(snippet)
        context.insert(folder)
        try context.save()
        let exported = directory.appendingPathComponent("snippets.xml")
        try LegacyMigration.exportSnippets(to: exported, from: context)
        check((try? LegacyMigration.importSnippets(from: exported, into: context))?.snippetsSkipped == 1, "XML snippet round trip and deduplication")
        try LegacyMigration.exportSnippets(to: exported, from: context)
        check((try? LegacyMigration.importSnippets(from: exported, into: context))?.snippetsSkipped == 1, "atomic replacement export")
        let legacy = directory.appendingPathComponent("legacy-snippets.xml")
        try """
        <?xml version="1.0" standalone="yes"?>
        <!DOCTYPE database SYSTEM "file:///System/Library/DTDs/CoreData.dtd">
        <database>
        <object type="FOLDER" id="z1">
        <attribute name="title" type="string">Legacy folder</attribute>
        <attribute name="index" type="int16">0</attribute>
        <attribute name="enabled" type="bool">1</attribute>
        <relationship name="snippets" type="0/0" destination="SNIPPET" idrefs="z2"></relationship>
        </object>
        <object type="SNIPPET" id="z2">
        <attribute name="title" type="string">Legacy snippet</attribute>
        <attribute name="index" type="int16">3</attribute>
        <attribute name="enabled" type="bool">0</attribute>
        <attribute name="content" type="string">legacy body</attribute>
        <relationship name="folder" type="1/1" destination="FOLDER" idrefs="z1"></relationship>
        </object>
        </database>
        """.write(to: legacy, atomically: true, encoding: .utf8)
        let legacyImport = try LegacyMigration.importSnippets(from: legacy, into: context)
        check(legacyImport.foldersAdded == 1 && legacyImport.snippetsAdded == 1, "original ClipMenu int16 snippet file")
        let legacySnippet = try context.fetch(FetchDescriptor<Snippet>()).first { $0.title == "Legacy snippet" }
        check(legacySnippet?.content == "legacy body" && legacySnippet?.isEnabled == false && legacySnippet?.sortIndex == 0, "original snippet text and disabled flag")
        let exportPermissions = try FileManager.default.attributesOfItem(atPath: exported.path)[.posixPermissions] as? NSNumber
        check(exportPermissions?.intValue == 0o600, "snippet export owner-only permissions")
        let original = try String(contentsOf: exported, encoding: .utf8)
        let malicious = directory.appendingPathComponent("malicious.xml")
        let dtd = "<!DOCTYPE database [<!ENTITY injected SYSTEM 'file:///etc/passwd'>]>"
        let withDTD = original.replacingOccurrences(of: "<database", with: dtd + "<database")
        check(withDTD != original, "DTD fixture inserted at database root")
        try withDTD.write(to: malicious, atomically: true, encoding: .utf8)
        check((try? LegacyMigration.importSnippets(from: malicious, into: context)) == nil, "external entity import rejected")
        let internalDTD = original.replacingOccurrences(of: "<database", with: "<!DOCTYPE database [<!ENTITY bomb 'expansion'>]><database")
        try internalDTD.write(to: malicious, atomically: true, encoding: .utf8)
        check((try? LegacyMigration.importSnippets(from: malicious, into: context)) == nil, "internal entity import rejected")
        let nested = String(repeating: "<nested>", count: 40) + String(repeating: "</nested>", count: 40)
        try nested.write(to: malicious, atomically: true, encoding: .utf8)
        check((try? LegacyMigration.importSnippets(from: malicious, into: context)) == nil, "deeply nested XML rejected")
        try Data(repeating: 32, count: LegacyMigration.maximumXMLBytes + 1).write(to: malicious)
        check((try? LegacyMigration.importSnippets(from: malicious, into: context)) == nil, "oversized XML rejected")
        check(try context.fetchCount(FetchDescriptor<Snippet>()) == 2, "invalid imports leave library intact")
        print("[SCRIPT SECURITY] PASS: \(checks) checks")
    }
}
