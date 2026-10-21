import AppKit
import SwiftData

@main
enum CoreServicesSmoke {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ description: String) {
            guard condition else {
                fputs("[CORE SMOKE] FAIL: \(description)\n", stderr)
                exit(1)
            }
            checks += 1
        }

        let engine = ScriptEngine()
        let input = ScriptableClip(text: "Mixed Case")
        check(engine.run(script: "return clipText.toUpperCase();", clip: input) == "MIXED CASE", "valid action")
        check(engine.run(script: "return (;", clip: input) == nil, "syntax error reused previous action")
        check(engine.run(script: "throw new Error('failure');", clip: input) == nil, "runtime error returned a result")
        check(engine.run(script: "return clip.text.toLowerCase(); // trailing comment", clip: input) == "mixed case", "action did not recover after errors")
        check(engine.run(script: "return;", clip: input) == nil, "undefined result")
        check(engine.run(script: "return null;", clip: input) == nil, "null result")

        let imageA = ClipEntry()
        imageA.types = [NSPasteboard.PasteboardType.tiff.rawValue]
        imageA.imageData = Data([1, 2, 3, 4])
        let imageB = ClipEntry()
        imageB.types = imageA.types
        imageB.imageData = Data([4, 3, 2, 1])
        check(imageA.contentHash == imageB.contentHash, "binary collision fixture")
        check(!imageA.hasSameContent(as: imageB), "different equal-length images deduplicated")
        imageB.imageData = imageA.imageData
        check(imageA.hasSameContent(as: imageB), "identical images not deduplicated")
        imageA.rtfData = Data([1, 2])
        imageB.rtfData = Data([2, 1])
        check(!imageA.hasSameContent(as: imageB), "different equal-length rich text deduplicated")

        let suite = "ClipMenu.CoreSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ClipMenuSettings(defaults: defaults)
        settings.excludeApps = []
        settings.reorderClipsAfterPasting = false
        settings.maxHistorySize = 2
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = ClipsService(settings: settings, pasteboard: board)
        let schema = Schema([ClipEntry.self, ActionNode.self, Snippet.self, SnippetFolder.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        for index in 0..<620 {
            let clip = ClipEntry()
            clip.stringValue = "clip \(index)"
            context.insert(clip)
        }
        try context.save()
        service.start(context: context)
        check(try context.fetchCount(FetchDescriptor<ClipEntry>()) == 2, "history shrink left more than the limit")
        service.stop()

        let first = try context.fetch(FetchDescriptor<ClipEntry>())[0]
        first.types = [NSPasteboard.PasteboardType.string.rawValue]
        first.lastUsedAt = .distantPast
        await service.select(first, pasteImmediately: false)
        check(first.lastUsedAt > .distantPast, "selection did not mark the current clip")
        check(board.string(forType: .string) == first.stringValue, "text pasteboard round trip")

        let files = ["/tmp/one file.txt", "/tmp/two-📝.txt"]
        board.clearContents()
        board.writeObjects(files.map { URL(fileURLWithPath: $0) as NSURL })
        guard let fileClip = service.makeClip(from: board) else { fatalError("file capture missing") }
        check(fileClip.filenames == files, "multi-file capture")
        await service.select(fileClip, pasteImmediately: false)
        let pastedFiles = (board.pasteboardItems ?? []).compactMap { $0.string(forType: .fileURL) }.compactMap(URL.init(string:)).map(\.path)
        check(pastedFiles == files, "multi-file pasteboard round trip")

        board.clearContents()
        board.setString("https://example.com/path?q=hello", forType: .URL)
        guard let urlClip = service.makeClip(from: board) else { fatalError("URL capture missing") }
        check(urlClip.urlStrings == ["https://example.com/path?q=hello"], "web URL capture")
        await service.select(urlClip, pasteImmediately: false)
        check(board.string(forType: .URL) == urlClip.urlStrings?.first, "web URL pasteboard round trip")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for pixel in 0..<4 {
            let offset = pixel * 4
            bitmap.bitmapData![offset] = 255
            bitmap.bitmapData![offset + 1] = 0
            bitmap.bitmapData![offset + 2] = 0
            bitmap.bitmapData![offset + 3] = 255
        }
        let png = bitmap.representation(using: .png, properties: [:])!
        board.clearContents()
        board.setData(png, forType: .png)
        guard let capturedImage = service.makeClip(from: board) else { fatalError("image capture missing") }
        check(capturedImage.types == [NSPasteboard.PasteboardType.tiff.rawValue], "image type normalization")
        check(capturedImage.imageData != png, "PNG bytes incorrectly labelled TIFF")
        await service.select(capturedImage, pasteImmediately: false)
        let decoded = board.data(forType: .tiff).flatMap(NSBitmapImageRep.init(data:))
        check(decoded?.pixelsWide == 2 && decoded?.pixelsHigh == 2, "image pasteboard round trip")
        capturedImage.imageData = png
        await service.select(capturedImage, pasteImmediately: false)
        check(board.data(forType: .tiff) != png, "old PNG capture remained incorrectly labelled TIFF")

        board.clearContents()
        board.setData(bitmap.tiffRepresentation!, forType: .tiff)
        await service.handlePasteboardChange(board)
        board.clearContents()
        bitmap.bitmapData![0] = 0
        bitmap.bitmapData![2] = 255
        board.setData(bitmap.tiffRepresentation!, forType: .tiff)
        await service.handlePasteboardChange(board)
        let captured = try context.fetch(FetchDescriptor<ClipEntry>())
        check(captured.count == 2 && captured.allSatisfy { $0.imageData != nil }, "binary hash collision lost a history entry: count=\(captured.count), data=\(captured.map { $0.imageData?.count ?? -1 })")
        await service.handlePasteboardChange(board)
        check(try context.fetchCount(FetchDescriptor<ClipEntry>()) == 2, "identical capture was inserted twice")

        print("[CORE SMOKE] PASS: \(checks) checks")
    }
}
