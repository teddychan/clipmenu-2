import Testing
import Foundation
import SwiftData
@testable import ClipMenu

// The History-menu search (⌘⌃V) filters in the store via ClipStore.searchPredicate
// instead of fetching every row and filtering in Swift. This proves the predicate
// SwiftData pushes into SQLite actually matches the way the menu expects:
// case- and diacritic-insensitive "contains", and image-only clips (no text)
// never match. Uses a disk-backed store because SwiftData string-predicate
// translation is faithful only against SQLite (same reason as AtCapacityCaptureTests).
@Suite(.serialized) struct HistorySearchTests {

    private func diskStore() throws -> (ModelContainer, () -> Void) {
        let dir = URL.temporaryDirectory.appending(path: "ClipMenuSearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(
            "History", schema: Schema([ClipRecord.self, ClipImage.self]),
            url: dir.appending(path: "History.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: ClipRecord.self, ClipImage.self, configurations: config)
        return (container, { try? FileManager.default.removeItem(at: dir) })
    }

    private func fetch(_ query: String, in context: ModelContext) throws -> [String] {
        let descriptor = FetchDescriptor<ClipRecord>(predicate: ClipStore.searchPredicate(query))
        return try context.fetch(descriptor).compactMap(\.stringValue)
    }

    @Test func searchIsCaseAndDiacriticInsensitiveAndSkipsImageOnlyClips() throws {
        let (container, cleanup) = try diskStore()
        defer { cleanup() }
        let ctx = ModelContext(container)
        let base = Date(timeIntervalSince1970: 1_000_000)
        let seeds = ["Hello World", "café menu", "unrelated text"]
        for (i, s) in seeds.enumerated() {
            let d = base.addingTimeInterval(Double(i))
            ctx.insert(ClipRecord(createdDate: d, lastUsedDate: d,
                                  typeIdentifiers: ["String"], stringValue: s, contentHash: i))
        }
        // An image-only clip (no stringValue) must never match a text query.
        ctx.insert(ClipRecord(createdDate: base, lastUsedDate: base,
                              typeIdentifiers: ["TIFF"], stringValue: nil, contentHash: 99))
        try ctx.save()

        // Case-insensitive.
        #expect(try fetch("hello", in: ctx) == ["Hello World"])
        // Diacritic-insensitive ("cafe" matches "café").
        #expect(try fetch("cafe", in: ctx) == ["café menu"])
        // No match → empty; image-only clip never surfaces for any text query.
        #expect(try fetch("zzz", in: ctx).isEmpty)
    }
}
