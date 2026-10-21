import AppKit
import ImageIO
import SwiftData

@main
enum ClipboardSecuritySmoke {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ description: String) {
            guard condition else {
                fputs("[CLIPBOARD SECURITY] FAIL: \(description)\n", stderr)
                exit(1)
            }
            checks += 1
        }

        // This test never opens NSPasteboard.general or the user's history.
        let suite = "ClipMenu.ClipboardSecurity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ClipMenuSettings(defaults: defaults)
        settings.excludeApps = []
        settings.autoPasteAfterSelection = false
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = ClipsService(settings: settings, pasteboard: board)
        let schema = Schema([ClipEntry.self, ActionNode.self, Snippet.self, SnippetFolder.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        service.start(context: container.mainContext)
        service.stop()

        func writeString(_ text: String) {
            board.clearContents()
            check(board.setString(text, forType: .string), "write synthetic text")
        }

        writeString("ordinary copy")
        check(service.makeClip(from: board)?.stringValue == "ordinary copy", "ordinary copies are retained")

        for marker in ClipsService.ignoredPasteboardTypes {
            writeString("synthetic secret")
            board.addTypes([marker], owner: nil)
            board.setData(Data(), forType: marker)
            check(service.makeClip(from: board) == nil, "reject empty privacy marker \(marker.rawValue)")
            await service.handlePasteboardChange(board)
        }
        check(try container.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 0,
              "marked secrets never reach persistent model context")

        let publicItem = NSPasteboardItem()
        publicItem.setString("ordinary first item", forType: .string)
        let concealedItem = NSPasteboardItem()
        concealedItem.setString("synthetic secret in second item", forType: .string)
        concealedItem.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        check(board.writeObjects([publicItem, concealedItem]), "write multi-item copy")
        check(service.makeClip(from: board) == nil, "a concealed later item rejects the whole copy")

        let excludedID = "org.clipmenu.security-fixture.excluded"
        settings.excludeApps = [["bundleIdentifier": excludedID, "name": "Synthetic source"]]
        writeString("synthetic excluded source")
        let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
        board.addTypes([sourceType], owner: nil)
        board.setString(excludedID, forType: sourceType)
        check(service.makeClip(from: board) == nil, "declared excluded source is rejected")
        board.setString("org.clipmenu.security-fixture.allowed", forType: sourceType)
        check(service.makeClip(from: board, observedBundleIdentifier: excludedID) == nil,
              "declared allowed source cannot override observed exclusion")
        settings.excludeApps = []

        writeString("old generation")
        let oldCount = board.changeCount
        writeString("new generation")
        check(service.makeClip(from: board, expectedChangeCount: oldCount) == nil,
              "queued event cannot read a newer clipboard generation")
        await service.handlePasteboardChange(board, expectedChangeCount: oldCount)
        check(try container.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 0,
              "stale generation never reaches model context")

        board.clearContents()
        board.setData(Data(repeating: 65, count: ClipsService.maximumTextBytes + 1), forType: .string)
        check(service.makeClip(from: board) == nil, "oversized text is rejected")
        board.clearContents()
        let largeRepresentation = Data(repeating: 0, count: ClipsService.maximumCaptureBytes / 2 + 1)
        board.setData(largeRepresentation, forType: .rtfd)
        board.addTypes([.pdf], owner: nil)
        board.setData(largeRepresentation, forType: .pdf)
        check(service.makeClip(from: board) == nil, "aggregate representation size is bounded")

        board.clearContents()
        let manyItems = (0...ClipsService.maximumItemCount).map { index -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString("fixture-\(index)", forType: .string)
            return item
        }
        check(board.writeObjects(manyItems), "write synthetic many-item copy")
        check(service.makeClip(from: board) == nil, "item count is bounded")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .calibratedRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        board.clearContents()
        board.setData(png, forType: .png)
        let imageClip = service.makeClip(from: board)
        check(imageClip?.imageData != nil && imageClip?.types == [NSPasteboard.PasteboardType.tiff.rawValue],
              "ordinary images still normalize to TIFF")
        check(ClipsService.imageFitsCaptureLimits(bitmap.tiffRepresentation!), "ordinary TIFF accepted")

        // An actual 1-bit 8,192-square image has a compact 8 MiB raster, but
        // exceeds the accepted pixel count. Use valid compressed pixels rather
        // than an inconsistent PNG header (which ImageIO rejects as malformed).
        let raster = Data(repeating: 0, count: 8_192 * 1_024)
        let provider = CGDataProvider(data: raster as CFData)!
        let largeImage = CGImage(width: 8_192, height: 8_192, bitsPerComponent: 1,
                                 bitsPerPixel: 1, bytesPerRow: 1_024,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                                 provider: provider, decode: nil, shouldInterpolate: false,
                                 intent: .defaultIntent)!
        let encodedImage = NSMutableData()
        let destination = CGImageDestinationCreateWithData(encodedImage, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, largeImage, nil)
        check(CGImageDestinationFinalize(destination), "encode oversized raster fixture")
        let largePNG = encodedImage as Data
        let imageSource = CGImageSourceCreateWithData(largePNG as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)!
        let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as! [String: Any]
        check((imageProperties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue == 8_192,
              "oversized raster fixture advertises its synthetic dimensions")
        check(!ClipsService.imageFitsCaptureLimits(largePNG), "oversized raster is rejected before decoding")
        board.clearContents()
        board.setData(largePNG, forType: .png)
        check(service.makeClip(from: board) == nil, "oversized image cannot enter history")
        board.clearContents()
        board.setData(Data("malformed image".utf8), forType: .tiff)
        check(service.makeClip(from: board) == nil, "malformed image is rejected")

        writeString("ordinary persisted fixture")
        await service.handlePasteboardChange(board)
        check(try container.mainContext.fetchCount(FetchDescriptor<ClipEntry>()) == 1,
              "ordinary capture reaches the isolated model context")
        print("[CLIPBOARD SECURITY] PASS: \(checks) checks; named pasteboard and in-memory history only")
    }
}
