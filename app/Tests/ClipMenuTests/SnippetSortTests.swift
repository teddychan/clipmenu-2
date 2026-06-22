import Testing
import Foundation
@testable import ClipMenu

@Suite struct SnippetSortTests {
    private struct Item { let title: String; let index: Int }

    private let items = [
        Item(title: "Swift header", index: 0),
        Item(title: ".gitignore", index: 1),
        Item(title: "MIT license", index: 2),
    ]

    private func titles(_ s: SnippetSort) -> [String] {
        s.ordered(items, title: { $0.title }, index: { $0.index }).map(\.title)
    }

    @Test func manualUsesIndexOrder() {
        #expect(titles(.manual) == ["Swift header", ".gitignore", "MIT license"])
    }

    @Test func nameAscendingIsAlphabetical() {
        #expect(titles(.nameAscending) == [".gitignore", "MIT license", "Swift header"])
    }

    @Test func nameDescendingReversesAscending() {
        #expect(titles(.nameDescending) == ["Swift header", "MIT license", ".gitignore"])
    }

    @Test func nameSortOrdersNumbersNaturally() {
        let numbered = [Item(title: "item10", index: 0), Item(title: "item2", index: 1)]
        let asc = SnippetSort.nameAscending.ordered(numbered, title: { $0.title }, index: { $0.index })
        #expect(asc.map(\.title) == ["item2", "item10"])
    }
}
