import Testing
@testable import ClipMenu

// Pins the history-export transforms (PARITY §H; ClipsController.m:323-457).

@Suite struct HistoryExportTests {

    @Test func separatorTags() {
        #expect(HistoryExport.separator(forTag: 0) == "")
        #expect(HistoryExport.separator(forTag: 1) == "\n")
        #expect(HistoryExport.separator(forTag: 2) == "\r\n")
        #expect(HistoryExport.separator(forTag: 3) == "\r")
        #expect(HistoryExport.separator(forTag: 4) == "\t")
        #expect(HistoryExport.separator(forTag: 5) == " ")
        #expect(HistoryExport.separator(forTag: 99) == "")   // default
    }

    @Test func singleFileTrailingSeparator() {
        #expect(HistoryExport.singleFileText(clipStrings: [], separatorTag: 1) == "")
        #expect(HistoryExport.singleFileText(clipStrings: ["x"], separatorTag: 0) == "x")
        // Separator trails every clip, including the last.
        #expect(HistoryExport.singleFileText(clipStrings: ["a", "b"], separatorTag: 1) == "a\nb\n")
        #expect(HistoryExport.singleFileText(clipStrings: ["a", "b"], separatorTag: 4) == "a\tb\t")
    }

    @Test func multipleFilesUse1BasedFullListIndex() {
        // Non-string clips (nil) still advance the index → gaps in filenames.
        let entries = HistoryExport.multipleFileEntries(orderedClipStrings: [nil, "a", nil, "b"])
        #expect(entries.map(\.filename) == ["2.txt", "4.txt"])
        #expect(entries.map(\.content) == ["a", "b"])
    }
}
