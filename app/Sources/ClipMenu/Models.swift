import Foundation
import SwiftData

// SwiftData persistence schema. Derived from SPEC.md:
//  - Snippets: §5.1 (Snippets.xcdatamodel → Folder / Snippet).
//  - Clipboard history: §4 / Clip.m (types, dates, per-type payloads).
// Replaces the legacy Core Data XML store + NSCoding Clip archive
// (see ARCHITECTURE.md §1 row 10 and §2 `Clip`).
// Builds with the Xcode toolchain (provides the SwiftDataMacros plugin).

// MARK: - Snippets

/// How a folder's snippets — or the folder list itself — are ordered in the
/// editor (issue #31). Sorting is a view transform: `index` always stores the
/// manual drag order, so switching back to `.manual` restores it.
enum SnippetSort: Int, Codable, CaseIterable, Sendable {
    case manual = 0           // hand-arranged drag order (uses `index`)
    case nameAscending = 1
    case nameDescending = 2

    /// Orders `items` by this mode. `.manual` sorts by `index` ascending; name
    /// sorts compare `title` with `localizedStandardCompare` (case/diacritic
    /// insensitive, natural number ordering — "item2" before "item10").
    func ordered<T>(_ items: [T], title: (T) -> String, index: (T) -> Int) -> [T] {
        switch self {
        case .manual:
            return items.sorted { index($0) < index($1) }
        case .nameAscending:
            return items.sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
        case .nameDescending:
            return items.sorted { title($0).localizedStandardCompare(title($1)) == .orderedDescending }
        }
    }
}

@Model
final class Folder {
    var title: String = ""
    var index: Int = 0

    /// This folder's snippet-sort mode (raw `SnippetSort`); persisted per folder.
    var snippetSortRaw: Int = 0
    /// Disclosure state in the editor outline; persisted.
    var isExpanded: Bool = true

    // Deleting a folder cascades to its snippets.
    // Optional to-many: CloudKit requires every relationship to be optional, or the
    // CloudKit-mirrored ModelContainer fails to load (Core Data error 134060). Read it
    // via `folder.snippets ?? []`.
    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder)
    var snippets: [Snippet]?

    /// Typed accessor for `snippetSortRaw`. Computed — not persisted by SwiftData.
    var snippetSort: SnippetSort {
        get { SnippetSort(rawValue: snippetSortRaw) ?? .manual }
        set { snippetSortRaw = newValue.rawValue }
    }

    init(title: String = L("untitled folder"), index: Int = 0) {
        self.title = title
        self.index = index
        self.snippets = []
    }
}

@Model
final class Snippet {
    var title: String = ""
    var content: String = ""
    var index: Int = 0
    var folder: Folder?

    init(
        title: String = L("untitled snippet"),
        content: String = "",
        index: Int = 0,
        folder: Folder? = nil
    ) {
        self.title = title
        self.content = content
        self.index = index
        self.folder = folder
    }
}

extension Snippet {
    /// A label auto-derived from a snippet's content: the first non-empty line,
    /// capped to 10 words / 60 chars. Returns `nil` when there's nothing usable
    /// (the caller falls back to the untitled default). Pure — unit-tested.
    static func derivedTitle(fromContent content: String) -> String? {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let capped = trimmed.split(separator: " ").prefix(10).joined(separator: " ")
        return capped.count > 60 ? String(capped.prefix(60)) : capped
    }
}

// MARK: - Clipboard history

/// One captured clipboard item. A clip may carry several representations at
/// once; `typeIdentifiers` records them in priority order (legacy `Clip.types`).
@Model
final class ClipRecord {
    var createdDate: Date
    var lastUsedDate: Date

    /// Pasteboard type identifiers (UTIs), highest-priority first.
    var typeIdentifiers: [String]

    // Per-type payloads (all optional; populated only for stored types).
    var stringValue: String?
    // Large binary payloads use external storage (CLAUDE.md §4/§7): SwiftData
    // writes them as separate files, keeping history rows small and loading the
    // bytes lazily (only when a clip is thumbnailed or pasted), not on every fetch.
    @Attribute(.externalStorage) var rtfData: Data?
    @Attribute(.externalStorage) var pdfData: Data?
    var filenames: [String]?
    var urlString: String?
    /// Original TIFF image bytes, kept byte-for-byte so paste reproduces the
    /// exact clipboard content. Held in a SEPARATE row (`ClipImage`) so the
    /// history menu's `ClipRecord` fetch never materializes the multi-MB blob —
    /// faulting a `ClipRecord` loads the whole row, and a large inline image
    /// column would come with it. The relationship is loaded lazily, only when
    /// a clip is actually pasted (CLAUDE.md §4).
    @Relationship(deleteRule: .cascade) var image: ClipImage?

    /// Small downsampled PNG thumbnail for menu display (a few tens of KB),
    /// generated once at capture. The menu renders from this so it never has to
    /// load the original image (CLAUDE.md §4). Display-only: it never goes back
    /// on the pasteboard.
    var thumbnailData: Data?

    /// Stable content fingerprint for de-duplication (legacy `Clip` hash,
    /// Clip.m:445-550). Two clips with the same content share a hash.
    var contentHash: Int

    init(
        createdDate: Date = .now,
        lastUsedDate: Date = .now,
        typeIdentifiers: [String] = [],
        stringValue: String? = nil,
        rtfData: Data? = nil,
        pdfData: Data? = nil,
        filenames: [String]? = nil,
        urlString: String? = nil,
        image: ClipImage? = nil,
        thumbnailData: Data? = nil,
        contentHash: Int = 0
    ) {
        self.createdDate = createdDate
        self.lastUsedDate = lastUsedDate
        self.typeIdentifiers = typeIdentifiers
        self.stringValue = stringValue
        self.rtfData = rtfData
        self.pdfData = pdfData
        self.filenames = filenames
        self.urlString = urlString
        self.image = image
        self.thumbnailData = thumbnailData
        self.contentHash = contentHash
    }
}

/// The original image bytes for an image clip, stored in its own row and loaded
/// only when the clip is pasted (see `ClipRecord.image`). Keeping the heavy blob
/// out of `ClipRecord` is what stops the menu from pulling images into memory.
@Model
final class ClipImage {
    @Attribute(.externalStorage) var data: Data

    init(data: Data) {
        self.data = data
    }
}
