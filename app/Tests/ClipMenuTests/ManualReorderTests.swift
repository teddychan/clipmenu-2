import Testing
import SwiftUI // for IndexSet
@testable import ClipMenu

/// Exhaustive characterization of `ManualReorder` — the pure array helpers the
/// snippet editor uses for manual drag-reorder and `index` renumbering. These
/// pin down CURRENT behavior (including SwiftUI's `move(fromOffsets:toOffset:)`
/// insert-before-destination semantics), so any change is a deliberate one.
@Suite struct ManualReorderTests {

    /// Generic element: `index` is the manual sort key; `id` identifies a row.
    private struct Item: Equatable { let id: Int; var index: Int }

    private func moved(_ items: [Item], from source: IndexSet, to dest: Int) -> [Item] {
        ManualReorder.moved(items, from: source, to: dest, index: { $0.index })
    }
    private func ids(_ items: [Item]) -> [Int] { items.map(\.id) }

    /// A tidy, already-index-sorted 0..<4 list (id == index) for the move cases.
    private let sorted4 = [
        Item(id: 0, index: 0),
        Item(id: 1, index: 1),
        Item(id: 2, index: 2),
        Item(id: 3, index: 3),
    ]

    // MARK: moved — sorts by index before applying the move

    @Test func movedSortsByIndexBeforeMoving() {
        // Array order (ids [1,2,3]) deliberately differs from index order.
        let unsorted = [
            Item(id: 1, index: 2),
            Item(id: 2, index: 0),
            Item(id: 3, index: 1),
        ]
        // Index order is [id2(0), id3(1), id1(2)]; moving offset 0 -> 2 on THAT.
        let result = moved(unsorted, from: IndexSet(integer: 0), to: 2)
        #expect(ids(result) == [3, 2, 1])
        // Sanity: had it NOT sorted first, the array-order path would give [2,1,3].
        #expect(ids(result) != [2, 1, 3])
    }

    @Test func movedSingleElementListIsUnchanged() {
        let one = [Item(id: 5, index: 0)]
        #expect(moved(one, from: IndexSet(integer: 0), to: 1) == one)
        #expect(moved(one, from: IndexSet(integer: 0), to: 0) == one)
    }

    @Test func movedItemDownFromZeroToThree() {
        // Drag row 0 down to slot 3: lands before the element originally at 3.
        let result = moved(sorted4, from: IndexSet(integer: 0), to: 3)
        #expect(ids(result) == [1, 2, 0, 3])
    }

    @Test func movedItemUpFromTwoToZero() {
        let result = moved(sorted4, from: IndexSet(integer: 2), to: 0)
        #expect(ids(result) == [2, 0, 1, 3])
    }

    @Test func movedToVeryEndDestinationEqualsCount() {
        let result = moved(sorted4, from: IndexSet(integer: 0), to: 4)
        #expect(ids(result) == [1, 2, 3, 0])
    }

    @Test func movedMultiOffsetToEnd() {
        let result = moved(sorted4, from: IndexSet([0, 1]), to: 4)
        #expect(ids(result) == [2, 3, 0, 1])
    }

    @Test func movedMultiOffsetIntoMiddle() {
        // Non-contiguous offsets keep their relative order at the destination.
        let result = moved(sorted4, from: IndexSet([0, 2]), to: 4)
        #expect(ids(result) == [1, 3, 0, 2])
    }

    @Test func movedNoOpWhenSourceAdjacentToDestination() {
        // Moving row 1 to offset 2 (just past itself) leaves order unchanged.
        #expect(moved(sorted4, from: IndexSet(integer: 1), to: 2) == sorted4)
        // Moving row 1 to offset 1 (before itself) is likewise a no-op.
        #expect(moved(sorted4, from: IndexSet(integer: 1), to: 1) == sorted4)
    }

    @Test func movedResultRenumbersToContiguousZeroBased() {
        // The documented contract: reassigning enumerated() positions to `index`
        // yields a gapless 0..<count sequence, whatever the move was.
        var result = moved(sorted4, from: IndexSet(integer: 0), to: 3)
        for (position, _) in result.enumerated() { result[position].index = position }
        #expect(result.map(\.index) == Array(0..<result.count))
    }

    // MARK: afterRemoving — survivors, sorted by index

    @Test func afterRemovingDropsMatchingIDAndSortsByIndex() {
        let items = [
            Item(id: 10, index: 2),
            Item(id: 20, index: 0),
            Item(id: 30, index: 1),
        ]
        let survivors = ManualReorder.afterRemoving(20, from: items,
                                                    id: { $0.id }, index: { $0.index })
        #expect(ids(survivors) == [30, 10]) // id20 gone; remainder in index order
    }

    @Test func afterRemovingIDNotPresentReturnsAllSorted() {
        let items = [
            Item(id: 10, index: 2),
            Item(id: 20, index: 0),
            Item(id: 30, index: 1),
        ]
        let survivors = ManualReorder.afterRemoving(999, from: items,
                                                    id: { $0.id }, index: { $0.index })
        #expect(ids(survivors) == [20, 30, 10])
    }

    @Test func afterRemovingEmptyInputReturnsEmpty() {
        let survivors = ManualReorder.afterRemoving(1, from: [Item](),
                                                    id: { $0.id }, index: { $0.index })
        #expect(survivors.isEmpty)
    }

    @Test func afterRemovingKeepsTiesAndGapsSortedStably() {
        // Tie on index 1 (ids 40 & 50) and a gap up to index 7.
        let items = [
            Item(id: 40, index: 1),
            Item(id: 50, index: 1),
            Item(id: 60, index: 7),
            Item(id: 70, index: 0),
        ]
        let survivors = ManualReorder.afterRemoving(60, from: items,
                                                    id: { $0.id }, index: { $0.index })
        // id70(0) first, then the two index-1 rows in their original relative order.
        #expect(ids(survivors) == [70, 40, 50])
    }

    // MARK: nextIndex — highest existing + 1, else 0

    @Test func nextIndexEmptyIsZero() {
        #expect(ManualReorder.nextIndex(in: [Item](), index: { $0.index }) == 0)
    }

    @Test func nextIndexContiguousIsCount() {
        let items = [Item(id: 0, index: 0), Item(id: 1, index: 1), Item(id: 2, index: 2)]
        #expect(ManualReorder.nextIndex(in: items, index: { $0.index }) == 3)
    }

    @Test func nextIndexWithGapsIsMaxPlusOne() {
        let items = [Item(id: 0, index: 0), Item(id: 1, index: 5), Item(id: 2, index: 2)]
        #expect(ManualReorder.nextIndex(in: items, index: { $0.index }) == 6)
    }

    @Test func nextIndexIgnoresDuplicatesUsingMax() {
        let items = [Item(id: 0, index: 2), Item(id: 1, index: 2)]
        #expect(ManualReorder.nextIndex(in: items, index: { $0.index }) == 3)
    }

    @Test func nextIndexWithNegativeIndices() {
        // Single -1 -> 0 (the empty-list sentinel and a real -1 collapse here).
        #expect(ManualReorder.nextIndex(in: [Item(id: 0, index: -1)], index: { $0.index }) == 0)
        // All-negative list returns max + 1, staying negative.
        let negatives = [Item(id: 0, index: -5), Item(id: 1, index: -2)]
        #expect(ManualReorder.nextIndex(in: negatives, index: { $0.index }) == -1)
    }
}
