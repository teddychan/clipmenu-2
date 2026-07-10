import Testing
import Foundation
@testable import ClipMenu

// Characterization of the HistoryExport file-writing effects (HistoryExport.swift
// lines 45-63) — the transforms themselves are pinned in HistoryExportTests.
@Suite struct HistoryExportCoverageTests {

    private func tempDir() throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "HistoryExport-\(UUID().uuidString)",
                                                    directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: writeSingleFile

    @Test func writeSingleFileEmptyHistoryIsNoOpButSucceeds() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "out.txt")

        #expect(HistoryExport.writeSingleFile(clipStrings: [], separatorTag: 1, to: url))
        // No file is written for an empty history.
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func writeSingleFileWritesJoinedTextWithTrailingSeparator() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "out.txt")

        #expect(HistoryExport.writeSingleFile(clipStrings: ["a", "b"], separatorTag: 1, to: url))
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == "a\nb\n")
    }

    @Test func writeSingleFileReturnsFalseOnUnwritablePath() {
        // A path whose parent directory does not exist cannot be written.
        let bad = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/dir/out.txt")
        #expect(HistoryExport.writeSingleFile(clipStrings: ["a"], separatorTag: 0, to: bad) == false)
    }

    // MARK: writeMultipleFiles

    @Test func writeMultipleFilesCreatesOneFilePerStringClipWith1BasedGaps() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // nil entries (non-string clips) still advance the index → gaps in names.
        #expect(HistoryExport.writeMultipleFiles(orderedClipStrings: [nil, "a", nil, "b"],
                                                 toDirectory: dir))
        #expect(try String(contentsOf: dir.appending(path: "2.txt"), encoding: .utf8) == "a")
        #expect(try String(contentsOf: dir.appending(path: "4.txt"), encoding: .utf8) == "b")
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "1.txt").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "3.txt").path))
    }

    @Test func writeMultipleFilesEmptyListSucceeds() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(HistoryExport.writeMultipleFiles(orderedClipStrings: [], toDirectory: dir))
        #expect(HistoryExport.writeMultipleFiles(orderedClipStrings: [nil, nil], toDirectory: dir))
    }

    @Test func writeMultipleFilesReturnsFalseWhenADirectoryIsUnwritable() {
        // Target directory does not exist → the first write fails → returns false.
        let bad = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/dir")
        #expect(HistoryExport.writeMultipleFiles(orderedClipStrings: ["a"], toDirectory: bad) == false)
    }
}
