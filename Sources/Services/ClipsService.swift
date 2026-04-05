import SwiftData
import AppKit
import Combine
import os

/// Manages the clipboard history: monitors NSPasteboard, deduplicates entries,
/// enforces the max-history limit, and writes ClipEntry records to SwiftData.
///
/// Reference: `legacy/Source/ClipsController.{h,m}` and `Clip.{h,m}`.
@MainActor
final class ClipsService {
    private static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "ClipsService")

    private let monitor    = ClipboardMonitor()
    private let exclusion  = AppExclusionService()
    private let paste      = PasteService()
    private let settings: ClipMenuSettings

    private var context:     ModelContext?
    private var cancellables = Set<AnyCancellable>()

    init(settings: ClipMenuSettings = ClipMenuSettings()) {
        self.settings = settings
    }

    func start(context: ModelContext) {
        self.context = context
        exclusion.update(from: settings)
        Task {
            await enforceHistoryLimitNow()
        }
        monitor.start()
        monitor.pasteboardChanged
            .sink { [weak self] pasteboard in
                Task {
                    await self?.handlePasteboardChange(pasteboard)
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        monitor.stop()
    }

    /// Copies the given entry back onto the system pasteboard and triggers paste.
    func select(_ entry: ClipEntry, pasteImmediately: Bool = true) async {
        let pboard = NSPasteboard.general
        pboard.clearContents()

        var declaredTypes = entry.types.map(NSPasteboard.PasteboardType.init(rawValue:))
        if declaredTypes.isEmpty {
            declaredTypes = [.string]
        }
        pboard.declareTypes(declaredTypes, owner: nil)

        for type in declaredTypes {
            switch type {
            case .string:
                if let value = entry.stringValue {
                    pboard.setString(value, forType: .string)
                }
            case .rtfd:
                if let data = entry.rtfData {
                    pboard.setData(data, forType: .rtfd)
                }
            case .rtf:
                if let data = entry.rtfData {
                    pboard.setData(data, forType: .rtf)
                }
            case .pdf:
                if let data = entry.pdfData {
                    pboard.setData(data, forType: .pdf)
                }
            case .fileURL:
                if let filenames = entry.filenames {
                    pboard.setPropertyList(filenames, forType: .fileURL)
                }
            case .URL:
                if let urls = entry.urlStrings {
                    pboard.setPropertyList(urls, forType: .URL)
                }
            case .tiff, .png:
                if let data = entry.imageData {
                    pboard.setData(data, forType: .tiff)
                }
            default:
                break
            }
        }

        entry.lastUsedAt = .now
        try? context?.save()

        if pasteImmediately && settings.autoPasteAfterSelection {
            Self.log.debug("Auto-paste after clip selection is ON (immediate)")
            await paste.paste()
        } else {
            Self.log.debug("Clip selected without immediate paste (pasteImmediately=\(pasteImmediately, privacy: .public), setting=\(self.settings.autoPasteAfterSelection, privacy: .public))")
        }
    }

    private func handlePasteboardChange(_ pboard: NSPasteboard) async {
        exclusion.update(from: settings)
        if exclusion.shouldExclude() {
            return
        }

        guard let clip = makeClip(from: pboard) else { return }
        guard let context else { return }

        do {
            let existing = try context.fetch(FetchDescriptor<ClipEntry>())
            if let matched = existing.first(where: { $0.contentHash == clip.contentHash }) {
                matched.lastUsedAt = .now
                if matched.imageData != nil || clip.imageData != nil {
                    Self.log.debug("Matched existing image clip hash=\(clip.contentHash, privacy: .public) imageBytes=\(clip.imageData?.count ?? 0, privacy: .public)")
                }
                try context.save()
                return
            }

            context.insert(clip)
            if clip.imageData != nil {
                Self.log.info("Inserted image clip hash=\(clip.contentHash, privacy: .public) imageBytes=\(clip.imageData?.count ?? 0, privacy: .public) types=\(clip.types.joined(separator: ","), privacy: .public)")
            }
            trimHistoryIfNeeded(context: context)
            try context.save()
        } catch {
            Self.log.error("Failed handling pasteboard change: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

    private func enforceHistoryLimitNow() async {
        guard let context else { return }
        trimHistoryIfNeeded(context: context)
        try? context.save()
    }

    private func trimHistoryIfNeeded(context: ModelContext) {
        do {
            var descriptor = FetchDescriptor<ClipEntry>(sortBy: [SortDescriptor(\ClipEntry.createdAt, order: .reverse)])
            descriptor.fetchLimit = max(settings.maxHistorySize, 0) + 500
            let clips = try context.fetch(descriptor)
            let maxSize = max(settings.maxHistorySize, 0)
            guard clips.count > maxSize else { return }

            for clip in clips[maxSize...] {
                context.delete(clip)
            }
        } catch {
            return
        }
    }

    private func makeClip(from pboard: NSPasteboard) -> ClipEntry? {
        guard let pbTypes = pboard.types, !pbTypes.isEmpty else { return nil }

        let filtered = filteredTypes(from: pbTypes)
        guard !filtered.isEmpty else { return nil }

        let clip = ClipEntry()
        clip.types = filtered.map(\.rawValue)

        for pbType in filtered {
            switch pbType {
            case .string:
                clip.stringValue = pboard.string(forType: .string)
            case .rtfd:
                clip.rtfData = pboard.data(forType: .rtfd)
                clip.isRTFD = true
            case .rtf:
                if clip.rtfData == nil {
                    clip.rtfData = pboard.data(forType: .rtf)
                    clip.isRTFD = false
                }
            case .pdf:
                clip.pdfData = pboard.data(forType: .pdf)
            case .fileURL:
                clip.filenames = pboard.propertyList(forType: .fileURL) as? [String]
            case .URL:
                clip.urlStrings = pboard.propertyList(forType: .URL) as? [String]
            case .tiff, .png:
                clip.imageData = pboard.data(forType: .tiff) ?? pboard.data(forType: .png)
                if clip.imageData == nil {
                    Self.log.debug("Image type seen but no image bytes. pbTypes=\(filtered.map(\.rawValue).joined(separator: ","), privacy: .public)")
                } else {
                    Self.log.debug("Captured image bytes=\(clip.imageData?.count ?? 0, privacy: .public)")
                }
            default:
                break
            }
        }

        return clip
    }

    private func filteredTypes(from pbTypes: [NSPasteboard.PasteboardType]) -> [NSPasteboard.PasteboardType] {
        var results: [NSPasteboard.PasteboardType] = []

        for pbType in pbTypes {
            guard shouldStore(pbType) else { continue }

            if pbType == .tiff || pbType == .png {
                if !results.contains(.tiff) {
                    results.append(.tiff)
                }
                continue
            }

            results.append(pbType)
        }

        return results
    }

    private func shouldStore(_ type: NSPasteboard.PasteboardType) -> Bool {
        guard let typeName = legacyTypeName(for: type) else { return false }
        return settings.storeTypes[typeName] ?? false
    }

    private func legacyTypeName(for type: NSPasteboard.PasteboardType) -> String? {
        switch type {
        case .string: return "String"
        case .rtf: return "RTF"
        case .rtfd: return "RTFD"
        case .pdf: return "PDF"
        case .fileURL: return "Filenames"
        case .URL: return "URL"
        case .tiff, .png: return "TIFF"
        default: return nil
        }
    }

    func clearAll() async throws {
        guard let context else { return }
        let all = try context.fetch(FetchDescriptor<ClipEntry>())
        for entry in all { context.delete(entry) }
        try context.save()
    }

    /// Writes a plain string to the pasteboard and triggers paste.
    func copyStringToPasteboard(_ string: String, pasteImmediately: Bool = true) async {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.setString(string, forType: .string)
        if pasteImmediately && settings.autoPasteAfterSelection {
            Self.log.debug("Auto-paste after snippet selection is ON (immediate)")
            await paste.paste()
        } else {
            Self.log.debug("Snippet copied without immediate paste (pasteImmediately=\(pasteImmediately, privacy: .public), setting=\(self.settings.autoPasteAfterSelection, privacy: .public))")
        }
    }
}
