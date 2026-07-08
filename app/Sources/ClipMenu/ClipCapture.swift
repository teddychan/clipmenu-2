import AppKit
import Foundation
import SwiftData

// Clipboard capture → SwiftData store. Mirrors ClipsController.m:
//  - _updateClips                  (587-649): dedup-by-hash bumps lastUsedDate, else add + trim
//  - _makeClipFromPasteboard       (651-729): per-type payload reads, RTFD-over-RTF, drop-when-empty
//  - _makeTypesFromPasteboard      (731-760): per-type store gating, TIFF/PICT fold
//  - _trimHistorySize              (795-813): drop oldest beyond maxHistorySize
//  - sortedClips                   (190-212): lastUsed (reorder) / created, descending
//
// PICT is dropped. Reading NSPasteboard happens off the main actor on
// the PasteboardMonitor actor (see PasteboardReader below); persistence runs
// off the main actor in a @ModelActor.

// MARK: - Supported types (the 7 live legacy types; Clip.m:110-136, PICT dropped)

/// Canonical legacy type names kept on `ClipRecord.typeIdentifiers` (priority order).
/// Using the legacy names keeps placeholder-title logic (row 44) simple.
enum ClipType {
    static func name(for type: NSPasteboard.PasteboardType) -> String? {
        switch type {
        case .string:  return "String"
        case .rtf:     return "RTF"
        case .rtfd:    return "RTFD"
        case .pdf:     return "PDF"
        case .fileURL: return "Filenames"
        case .URL:     return "URL"
        case .tiff:    return "TIFF"
        default:       return nil
        }
    }
}

// MARK: - Sendable snapshot (handed from the main actor to the store actor)

struct PasteboardSnapshot: Sendable {
    var typeNames: [String]          // legacy names, priority order (ClipRecord.typeIdentifiers)
    var stringValue: String?
    var rtfData: Data?
    var pdfData: Data?
    var filenames: [String]?
    var urlString: String?
    var imageData: Data?             // original TIFF bytes (menu thumbnail row 53 downsamples)
    var contentHash: Int             // stable content fingerprint for de-dup
}

// MARK: - Pasteboard read (off the main actor)

// Runs on the caller's executor — the PasteboardMonitor actor — so multi-MB
// payload copies (full TIFF/PDF/RTFD, and synchronous resolution of promised
// pasteboard data) never stall the main actor (CLAUDE.md §3). NSPasteboard is
// not Sendable but is not @MainActor-bound either: each call obtains
// NSPasteboard.general locally and never sends it across an isolation
// boundary; only the Sendable PasteboardSnapshot crosses actors.
enum PasteboardReader {
    /// Build a snapshot from the general pasteboard, honoring per-type store
    /// gating and TIFF/PICT folding. Returns nil when nothing storable remains
    /// (ClipsController.m:670-678).
    static func snapshot() -> PasteboardSnapshot? {
        // Skip capture when the frontmost app is excluded (ClipsController.m:606-608,
        // 768-793; default exclude list = OpenOffice.org, AppController.m:103-118).
        if frontAppIsExcluded() { return nil }

        let pboard = NSPasteboard.general
        guard let available = pboard.types else { return nil }

        // Honor the nspasteboard.org privacy markers: password managers mark
        // secrets / transient / auto-generated writes with these types and
        // expect clipboard recorders to skip the change entirely.
        if containsPrivacyMarker(available.map(\.rawValue)) { return nil }

        let store = storeTypes()
        // If the user disabled every type, store nothing (ClipsController.m:675-678).
        guard store.values.contains(true) else { return nil }

        // Ordered, gated, TIFF/PICT-folded type names (ClipsController.m:731-760).
        var names: [String] = []
        for type in available {
            guard let name = ClipType.name(for: type) else { continue }
            guard store[name, default: true] else { continue }
            if name == "TIFF", names.contains("TIFF") { continue }
            if !names.contains(name) { names.append(name) }
        }
        guard !names.isEmpty else { return nil }

        var stringValue: String?
        var rtfData: Data?
        var pdfData: Data?
        var filenames: [String]?
        var urlString: String?
        var imageData: Data?

        for name in names {
            switch name {
            case "String":
                stringValue = pboard.string(forType: .string)
            case "RTFD":
                rtfData = pboard.data(forType: .rtfd)
            case "RTF":
                if rtfData == nil { rtfData = pboard.data(forType: .rtf) } // RTFD wins (ClipsController.m:697)
            case "PDF":
                pdfData = pboard.data(forType: .pdf)
            case "Filenames":
                let urls = pboard.readObjects(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                ) as? [URL]
                filenames = urls?.map(\.path)
            case "URL":
                urlString = NSURL(from: pboard)?.absoluteString
            case "TIFF":
                if NSImage.canInit(with: pboard) {
                    imageData = pboard.data(forType: .tiff)
                }
            default:
                break
            }
        }

        let hash = stableContentHash(
            typeNames: names, stringValue: stringValue, rtfData: rtfData,
            pdfData: pdfData, filenames: filenames, urlString: urlString, imageData: imageData
        )

        return PasteboardSnapshot(
            typeNames: names, stringValue: stringValue, rtfData: rtfData, pdfData: pdfData,
            filenames: filenames, urlString: urlString, imageData: imageData, contentHash: hash
        )
    }

    /// Pasteboard types that mark a clipboard write as not-for-recording
    /// (nspasteboard.org de facto standard, used by 1Password, Bitwarden,
    /// KeePassXC, Dashlane, …). Pure helper so the rule is unit-testable.
    static func containsPrivacyMarker(_ typeNames: [String]) -> Bool {
        let markers: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
        ]
        return typeNames.contains(where: markers.contains)
    }

    /// Per-type store toggles, default all-YES (AppController.m:142, 48-58).
    private static func storeTypes() -> [String: Bool] {
        let names = ["String", "RTF", "RTFD", "PDF", "Filenames", "URL", "TIFF"]
        let stored = UserDefaults.standard.dictionary(forKey: PreferenceKeys.storeTypes) as? [String: Bool]
        var result: [String: Bool] = [:]
        for name in names { result[name] = stored?[name] ?? true }
        return result
    }

    /// True if the frontmost app's bundle id is in the exclude list
    /// (ClipsController.m:768-793, `_frontProcessIsInExcludeList`).
    private static func frontAppIsExcluded() -> Bool {
        isExcluded(currentFrontBundleID(), in: excludedBundleIdentifiers())
    }

    /// The frontmost app's bundle id, or nil. Read on the caller's (off-main)
    /// executor, matching the rest of the snapshot read; NSWorkspace's frontmost
    /// query is safe from any thread.
    static func currentFrontBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Whether `bundleID` is excluded. Pure so the exclusion rule — and the
    /// monitor's copy-then-switch guard (PasteboardMonitor) — is unit-testable.
    static func isExcluded(_ bundleID: String?, in excluded: Set<String>) -> Bool {
        guard let bundleID, !excluded.isEmpty else { return false }
        return excluded.contains(bundleID)
    }

    /// Excluded app bundle identifiers from the `excludeApps` default; falls back
    /// to the legacy default of OpenOffice.org (AppController.m:103-118).
    static func excludedBundleIdentifiers() -> Set<String> {
        if let list = UserDefaults.standard.array(forKey: PreferenceKeys.excludeApps) as? [[String: String]] {
            return Set(list.compactMap { $0["bundleIdentifier"] })
        }
        return ["org.openoffice.script"]
    }
}

/// Stable content fingerprint (FNV-1a) over the clip's actual stored content.
/// Stable across launches (unlike `Hasher`), which persisted de-dup needs.
func stableContentHash(
    typeNames: [String], stringValue: String?, rtfData: Data?, pdfData: Data?,
    filenames: [String]?, urlString: String?, imageData: Data?
) -> Int {
    var hash: UInt64 = 1469598103934665603
    func feed(_ byte: UInt8) {
        hash = (hash ^ UInt64(byte)) &* 1099511628211
    }
    func feed(_ s: String) {
        for byte in s.utf8 { feed(byte) }
    }
    func feed(_ data: Data?, label: String) {
        guard let data else {
            feed("\(label):0")
            return
        }
        feed("\(label):\(data.count):")
        for byte in data { feed(byte) }
    }
    feed(typeNames.joined(separator: ","))
    if let stringValue { feed("s:" + stringValue) }
    if let filenames { feed("f:" + filenames.joined(separator: "\n")) }
    if let urlString { feed("u:" + urlString) }
    feed(rtfData, label: "rtf")
    feed(pdfData, label: "pdf")
    feed(imageData, label: "img")
    return Int(bitPattern: UInt(truncatingIfNeeded: hash))
}

// MARK: - Store actor (off the main actor)

@ModelActor
actor ClipStore {
    /// Capture a snapshot: bump lastUsedDate if an identical clip exists
    /// (ClipsController.m:619-636), else insert + trim (642-643).
    func capture(_ snapshot: PasteboardSnapshot) {
        let hash = snapshot.contentHash
        let existing = FetchDescriptor<ClipRecord>(predicate: #Predicate { $0.contentHash == hash })
        if let match = try? modelContext.fetch(existing).first {
            match.lastUsedDate = Date()
            try? modelContext.save()
            return
        }

        // Derive the small display thumbnail now (off the main actor). The
        // original bytes are stored untouched for byte-exact paste (CLAUDE.md §4).
        let thumbnailData = snapshot.imageData.flatMap(Thumbnailer.makeThumbnailData(from:))

        let record = ClipRecord(
            createdDate: Date(),
            lastUsedDate: Date(),
            typeIdentifiers: snapshot.typeNames,
            stringValue: snapshot.stringValue,
            rtfData: snapshot.rtfData,
            pdfData: snapshot.pdfData,
            filenames: snapshot.filenames,
            urlString: snapshot.urlString,
            image: snapshot.imageData.map(ClipImage.init(data:)),
            thumbnailData: thumbnailData,
            contentHash: hash
        )
        modelContext.insert(record)
        trim()
        try? modelContext.save()
    }

    /// One-time migration: generate the small `thumbnailData` for image clips
    /// captured before thumbnails were stored, so they still show a picture in
    /// the menu. Memory-safe — each full image is read in its own short-lived
    /// context and released before the next, so peak usage is one image, not the
    /// whole history. Idempotent: after the first run no image clip lacks a
    /// thumbnail, so nothing is processed.
    func backfillThumbnails() {
        var descriptor = FetchDescriptor<ClipRecord>(predicate: #Predicate { $0.thumbnailData == nil })
        descriptor.propertiesToFetch = [\.typeIdentifiers]
        guard let candidates = try? modelContext.fetch(descriptor) else { return }
        let ids = candidates
            .filter { $0.typeIdentifiers.contains("TIFF") }
            .map(\.persistentModelID)
        guard !ids.isEmpty else { return }

        for id in ids {
            let context = ModelContext(modelContainer)
            guard let clip = context.model(for: id) as? ClipRecord,
                  let data = clip.image?.data,
                  let thumbnail = Thumbnailer.makeThumbnailData(from: data) else { continue }
            clip.thumbnailData = thumbnail
            try? context.save()
            // `context` is released here, freeing the faulted full image.
        }
    }

    /// Drop oldest clips beyond maxHistorySize (ClipsController.m:795-813). Runs on
    /// every capture, so it fetches only the overflow (offset past the cap), not the
    /// whole sorted history — with the `lastUsedDate`/`createdDate` index this stays
    /// cheap even under rapid copies and a large history (CLAUDE.md §2).
    private func trim() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<ClipRecord>())) ?? 0
        guard count > Self.maxHistorySize() else { return }
        guard let overflow = try? modelContext.fetch(Self.trimOverflowDescriptor()) else { return }
        for record in overflow {
            modelContext.delete(record)
        }
    }

    /// Sort: lastUsedDate (reorder, default) else createdDate, descending
    /// (ClipsController.m:190-212; reorder default AppController.m:134).
    static var sortDescriptor: SortDescriptor<ClipRecord> {
        let reorder = UserDefaults.standard.object(forKey: PreferenceKeys.reorderClipsAfterPasting) as? Bool ?? true
        return reorder
            ? SortDescriptor(\ClipRecord.lastUsedDate, order: .reverse)
            : SortDescriptor(\ClipRecord.createdDate, order: .reverse)
    }

    /// The user's configured history cap (default 20). Single source of truth for
    /// the bound applied everywhere clip history is materialized — storage
    /// (`trim`), the menu and its search, history export, and the upgrade
    /// migration — so the on-disk and in-view history never exceed it (CLAUDE.md §2/§4).
    static func maxHistorySize(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: PreferenceKeys.maxHistorySize) as? Int ?? 20
    }

    /// Newest-first fetch of the visible history, capped to `maxHistorySize`. The
    /// `ClipRecord.image` relationship stays faulted, so this never loads the
    /// multi-MB originals — callers that only need text/thumbnails (menu, search,
    /// export) pay nothing for image clips.
    static func boundedHistoryDescriptor(_ defaults: UserDefaults = .standard) -> FetchDescriptor<ClipRecord> {
        var descriptor = FetchDescriptor<ClipRecord>(sortBy: [sortDescriptor])
        descriptor.fetchLimit = maxHistorySize(defaults)
        return descriptor
    }

    /// The overflow to drop in `trim()`: the clips PAST `maxHistorySize` in the
    /// same newest-first order, selected with the cap as a fetch offset. Symmetric
    /// with `boundedHistoryDescriptor` — what that keeps, this deletes — so the
    /// on-disk history matches the in-view cap. Only the `contentHash` column is
    /// faulted, never the image payloads.
    static func trimOverflowDescriptor(_ defaults: UserDefaults = .standard) -> FetchDescriptor<ClipRecord> {
        var descriptor = FetchDescriptor<ClipRecord>(sortBy: [sortDescriptor])
        descriptor.fetchOffset = maxHistorySize(defaults)
        descriptor.propertiesToFetch = [\.contentHash]
        return descriptor
    }
}
