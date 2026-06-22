import Testing
@testable import ClipMenu

// Numeric key-equivalents: the first ten clips (0-based index 0…9) get
// "1"…"9","0"; the 11th (index 10) must get "" — never the two-character
// "11", which is not a valid single-character NSMenuItem key equivalent.

@Suite @MainActor
struct ClipKeyEquivalentTests {
    private func eq(_ i: Int) -> String {
        MainMenuController.numericKeyEquivalent(forIndex: i, enabled: true)
    }

    @Test func firstTenGetDigitsThenZero() {
        #expect((0..<9).map(eq) == ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
        #expect(eq(9) == "0")
    }

    @Test func eleventhAndBeyondGetNone() {
        #expect(eq(10) == "")
        #expect(eq(11) == "")
        #expect(eq(99) == "")
    }

    @Test func disabledGivesNone() {
        #expect(MainMenuController.numericKeyEquivalent(forIndex: 0, enabled: false) == "")
    }
}
