import Testing
import Foundation
import SwiftData
@testable import ClipMenu

// Regression: a full history must not stop accepting new clips. When the store is
// exactly at maxHistorySize, capture() must persist the new clip and trim the
// OLDEST — not drop the just-captured one. Guards the v2.17.7 bug where trim()
// ran before save() and its fetchOffset descriptor selected the still-pending
// insert as the "overflow", silently discarding every new copy once full.
//
// Serialized + uses a disk-backed store because capture()/trim() read
// maxHistorySize from UserDefaults.standard and #Index/offset ordering only
// applies to on-disk (SQLite) stores.
@Suite(.serialized) struct AtCapacityCaptureTests {

    @Test func captureWhenAtCapacityKeepsNewClipAndTrimsOldest() async throws {
        let dir = URL.temporaryDirectory.appending(path: "ClipMenuAtCap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = ModelConfiguration(
            "History", schema: Schema([ClipRecord.self, ClipImage.self]),
            url: dir.appending(path: "History.store"), cloudKitDatabase: .none)

        let cap = 5
        let previous = UserDefaults.standard.object(forKey: PreferenceKeys.maxHistorySize)
        UserDefaults.standard.set(cap, forKey: PreferenceKeys.maxHistorySize)
        defer { UserDefaults.standard.set(previous, forKey: PreferenceKeys.maxHistorySize) }

        // Seed exactly `cap` rows (contentHash 0..<cap), oldest first.
        let container = try ModelContainer(for: ClipRecord.self, ClipImage.self, configurations: config)
        let seed = ModelContext(container)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0 ..< cap {
            let d = base.addingTimeInterval(Double(i))
            seed.insert(ClipRecord(createdDate: d, lastUsedDate: d,
                                   typeIdentifiers: ["String"], stringValue: "seed\(i)", contentHash: i))
        }
        try seed.save()

        // Capture a brand-new clip through the real path.
        let store = ClipStore(modelContainer: container)
        let newHash = 999_999
        await store.capture(PasteboardSnapshot(
            typeNames: ["String"], stringValue: "BRAND NEW", rtfData: nil, pdfData: nil,
            filenames: nil, urlString: nil, imageData: nil, contentHash: newHash))

        // Reopen the store from disk and assert: new clip present, oldest gone, cap held.
        let ctx = ModelContext(try ModelContainer(for: ClipRecord.self, ClipImage.self, configurations: config))
        let hashes = Set(try ctx.fetch(FetchDescriptor<ClipRecord>()).map(\.contentHash))
        #expect(hashes.contains(newHash), "new clip must be saved even when history is at capacity")
        #expect(!hashes.contains(0), "the oldest clip should be the one trimmed")
        #expect(hashes.count == cap, "history should stay at the cap")
    }
}
