import Testing
@testable import ClipMenu

// A clip stores ONE rich-text blob (rtfData), and capture prefers RTFD when
// both RTF and RTFD are on the source pasteboard. Flat-RTFD bytes are not
// valid RTF, so paste must only offer the type the blob actually is — never
// declare public.rtf with RTFD bytes behind it.

@Suite @MainActor
struct PasterTypeTests {

    @Test func rtfIsDroppedWhenBlobIsRTFD() {
        #expect(Paster.offeredTypeNames(for: ["RTFD", "RTF", "String"])
                == ["RTFD", "String"])
    }

    @Test func rtfIsKeptWhenItIsTheOnlyRichType() {
        #expect(Paster.offeredTypeNames(for: ["RTF", "String"])
                == ["RTF", "String"])
    }

    @Test func unrelatedTypesPassThrough() {
        #expect(Paster.offeredTypeNames(for: ["String", "TIFF"])
                == ["String", "TIFF"])
    }
}
