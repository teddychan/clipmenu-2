import Foundation

// Export clipboard history to text (PARITY §H; ClipsController.m:323-408 single
// file, 410-457 multiple files; separators constants.h:30-35). The transforms
// are pure + tested; the Export… button + save panel that invoke them live in
// the §J General preferences pane (later).

enum HistoryExport {

    /// Separator for the single-file export, by the CMPrefTagOfSeparatorFor…
    /// tag (ClipsController.m:343-366).
    static func separator(forTag tag: Int) -> String {
        switch tag {
        case 1: return "\n"      // kNewLine
        case 2: return "\r\n"    // kCarriageReturnAndNewLine
        case 3: return "\r"      // kCarriageReturn
        case 4: return "\t"      // kTab
        case 5: return " "       // kSingleSpace
        default: return ""       // 0 / default: kEmptyString
        }
    }

    /// Single-file body: each string clip's value followed by the separator, in
    /// order (ClipsController.m:382-385 — separator trails every clip, including
    /// the last). `clipStrings` is already filtered to string-bearing clips.
    static func singleFileText(clipStrings: [String], separatorTag tag: Int) -> String {
        let sep = separator(forTag: tag)
        return clipStrings.map { $0 + sep }.joined()
    }

    /// Per-file entries for the multiple-files export: one `<i>.txt` per string
    /// clip, where `i` is the 1-based index in the FULL ordered list — the legacy
    /// counter increments for every clip, so non-string clips leave gaps
    /// (ClipsController.m:424-441). `orderedClipStrings` is the full sorted list;
    /// nil entries are non-string clips.
    static func multipleFileEntries(orderedClipStrings: [String?]) -> [(filename: String, content: String)] {
        orderedClipStrings.enumerated().compactMap { index, string in
            guard let string else { return nil }
            return (filename: "\(index + 1).txt", content: string)
        }
    }

    // MARK: - Effects

    /// Write the single-file export to `url` (overwrites).
    @discardableResult
    static func writeSingleFile(clipStrings: [String], separatorTag tag: Int, to url: URL) -> Bool {
        guard !clipStrings.isEmpty else { return true }   // empty history → no-op (323-326)
        let text = singleFileText(clipStrings: clipStrings, separatorTag: tag)
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    /// Write `<i>.txt` files into `directory`.
    @discardableResult
    static func writeMultipleFiles(orderedClipStrings: [String?], toDirectory directory: URL) -> Bool {
        for entry in multipleFileEntries(orderedClipStrings: orderedClipStrings) {
            let url = directory.appendingPathComponent(entry.filename)
            if (try? entry.content.write(to: url, atomically: true, encoding: .utf8)) == nil {
                return false
            }
        }
        return true
    }
}
