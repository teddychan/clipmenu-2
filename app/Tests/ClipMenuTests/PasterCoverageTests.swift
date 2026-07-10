import Testing
import AppKit
@testable import ClipMenu

// Characterization tests for the pasteboard-writing helpers in Paster. The
// actual ⌘V synthesis (postCommandV / the Accessibility prompt) cannot run
// headlessly and is documented as uncoverable; everything that prepares the
// pasteboard before that runs fine in the test process against
// NSPasteboard.general, so we assert exactly what gets written.
//
// Serialized + save/restore because these mutate the shared general pasteboard
// and (for the paste() gate) UserDefaults.standard.
@Suite(.serialized) @MainActor
struct PasterCoverageTests {

    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    // MARK: copy(string:)

    @Test func copyStringDeclaresOnlyStringType() {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        Paster.copy(string: "hello snippet")
        #expect(pboard.string(forType: .string) == "hello snippet")
        // AppKit auto-declares legacy plain-text aliases alongside .string.
        #expect(pboard.types?.contains(.string) == true)
        #expect(pboard.types?.contains(.rtf) == false)
    }

    // MARK: copy(rtfData:isRTFD:)

    @Test func copyRTFDataAsPlainRTF() {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        let bytes = Data("{\\rtf1 plain}".utf8)
        Paster.copy(rtfData: bytes, isRTFD: false)
        #expect(pboard.data(forType: .rtf) == bytes)
        #expect(pboard.types?.contains(.rtf) == true)
        #expect(pboard.types?.contains(.rtfd) == false)
        #expect(pboard.data(forType: .rtfd) == nil)
    }

    @Test func copyRTFDataAsRTFD() {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        Paster.copy(rtfData: bytes, isRTFD: true)
        #expect(pboard.data(forType: .rtfd) == bytes)
        #expect(pboard.types?.contains(.rtfd) == true)
        #expect(pboard.types?.contains(.rtf) == false)
        #expect(pboard.data(forType: .rtf) == nil)
    }

    // MARK: copy(_ clip:)

    @Test func copyClipWritesEveryOfferedTypeAndDropsRTFWhenRTFDPresent() {
        let pboard = NSPasteboard.general
        pboard.clearContents()

        let rtfd = Data([0xAA, 0xBB, 0xCC])
        let pdf = Data("%PDF-1.4".utf8)
        let tiff = Data([0x4D, 0x4D, 0x00, 0x2A])
        let clip = ClipRecord(
            typeIdentifiers: ["RTFD", "RTF", "String", "URL", "PDF", "Filenames", "TIFF"],
            stringValue: "plain text",
            rtfData: rtfd,
            pdfData: pdf,
            filenames: ["/tmp/a.txt", "/tmp/b.txt"],
            urlString: "https://example.com",
            image: ClipImage(data: tiff),
            contentHash: 7
        )
        Paster.copy(clip)

        // RTF is dropped because the blob is RTFD (see offeredTypeNames).
        #expect(pboard.types?.contains(.rtf) == false)
        #expect(pboard.data(forType: .rtf) == nil)

        #expect(pboard.data(forType: .rtfd) == rtfd)
        #expect(pboard.string(forType: .string) == "plain text")
        #expect(pboard.string(forType: .URL) == "https://example.com")
        #expect(pboard.data(forType: .pdf) == pdf)
        #expect(pboard.data(forType: .tiff) == tiff)
        #expect(pboard.propertyList(forType: Self.filenamesType) as? [String]
                == ["/tmp/a.txt", "/tmp/b.txt"])
    }

    @Test func copyClipKeepsRTFWhenItIsTheOnlyRichType() {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        let rtf = Data("{\\rtf1 only}".utf8)
        let clip = ClipRecord(
            typeIdentifiers: ["RTF", "String"],
            stringValue: "s",
            rtfData: rtf,
            contentHash: 1
        )
        Paster.copy(clip)
        #expect(pboard.data(forType: .rtf) == rtf)
        #expect(pboard.string(forType: .string) == "s")
    }

    @Test func copyClipWithMissingPayloadsDeclaresTypesButWritesNothing() {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        // typeIdentifiers claim String/URL but the payloads are nil: the type is
        // declared, yet no value is set for it.
        let clip = ClipRecord(typeIdentifiers: ["String", "URL"], contentHash: 2)
        Paster.copy(clip)
        #expect(pboard.types?.contains(.string) == true)
        #expect(pboard.types?.contains(.URL) == true)
        #expect(pboard.string(forType: .string) == nil)
    }

    // MARK: paste() gate (the only headless-safe branch)

    @Test func pasteIsSkippedWhenInputPasteCommandPrefIsOff() {
        let key = PreferenceKeys.inputPasteCommand
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        // With the pref off, paste() returns false before ever touching
        // Accessibility (so no system prompt is triggered in the test process).
        UserDefaults.standard.set(false, forKey: key)
        #expect(Paster.paste() == false)
    }
}
