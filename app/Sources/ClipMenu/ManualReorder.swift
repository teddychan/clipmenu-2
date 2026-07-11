import SwiftUI

// Pure array helpers for the snippet editor's manual drag-reorder and `index`
// renumbering (extracted from SnippetEditorView so this arithmetic — the
// bug-prone part of "layout movement" — is unit-testable without a rendered
// SwiftUI view). `index` always stores the manual drag order; a name sort is a
// view transform that never rewrites it (SnippetEditorView header comment).
enum ManualReorder {

    /// `items` taken in ascending-`index` order with a SwiftUI `.onMove`
    /// (`source` offsets → `destination`) applied. Assigning each returned
    /// element's position back to its `index` yields a contiguous 0-based order.
    static func moved<T>(_ items: [T], from source: IndexSet, to destination: Int,
                         index: (T) -> Int) -> [T] {
        var ordered = items.sorted { index($0) < index($1) }
        ordered.move(fromOffsets: source, toOffset: destination)
        return ordered
    }

    /// The survivors after deleting the element whose id equals `removedID`, in
    /// ascending-`index` order — ready to renumber 0..<count.
    static func afterRemoving<T, ID: Equatable>(_ removedID: ID, from items: [T],
                                                id: (T) -> ID, index: (T) -> Int) -> [T] {
        items.filter { id($0) != removedID }.sorted { index($0) < index($1) }
    }

    /// The next append index for a manual list (highest existing + 1, else 0 when
    /// empty). Matches the legacy `(map(\.index).max() ?? -1) + 1` idiom.
    static func nextIndex<T>(in items: [T], index: (T) -> Int) -> Int {
        (items.map(index).max() ?? -1) + 1
    }
}
