import Testing
import AppKit
@testable import ClipMenu

// Characterization tests for Thumbnailer. Real image bytes are synthesized in the
// test process (NSBitmapImageRep → TIFF), which ImageIO decodes fine headlessly,
// so the downsample / aspect-fit / caching logic is fully exercisable. The pure
// fitSize math and displayScale fallback are covered directly.
@Suite(.serialized) @MainActor
struct ThumbnailerCoverageTests {

    /// A valid TIFF of the given pixel dimensions.
    private func tiff(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .tiff, properties: [:])!
    }

    private func maxDimension(of data: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: data) else { return 0 }
        return max(rep.pixelsWide, rep.pixelsHigh)
    }

    // MARK: makeThumbnailData

    @Test func makeThumbnailDataDownsamplesLargeImageToBound() throws {
        let source = tiff(width: 1024, height: 512)
        let out = try #require(Thumbnailer.makeThumbnailData(from: source))
        // Bounded by storedMaxPixelSize on the longest side.
        #expect(maxDimension(of: out) <= Thumbnailer.storedMaxPixelSize)
        // PNG output (magic bytes) and smaller than the original.
        #expect(out.prefix(4).elementsEqual([0x89, 0x50, 0x4E, 0x47]))
        #expect(out.count < source.count)
    }

    @Test func makeThumbnailDataReturnsNilForUndecodableBytes() {
        #expect(Thumbnailer.makeThumbnailData(from: Data()) == nil)
        #expect(Thumbnailer.makeThumbnailData(from: Data([0x00, 0x01, 0x02, 0x03])) == nil)
    }

    // MARK: makeThumbnail (NSImage)

    @Test func makeThumbnailProducesAspectFitImage() throws {
        let source = tiff(width: 200, height: 100)
        let image = try #require(Thumbnailer.makeThumbnail(from: source, fitting: NSSize(width: 50, height: 50), scale: 2))
        // Landscape 2:1 fit into a 50×50 box ⇒ 50×25 points.
        #expect(image.size == NSSize(width: 50, height: 25))
    }

    @Test func makeThumbnailReturnsNilForUndecodableBytes() {
        #expect(Thumbnailer.makeThumbnail(from: Data([0xFF, 0xFF]), fitting: NSSize(width: 32, height: 32)) == nil)
    }

    // MARK: fitSize

    @Test func fitSizeLandscapeFitsWidth() {
        #expect(Thumbnailer.fitSize(width: 200, height: 100, box: NSSize(width: 100, height: 100))
                == NSSize(width: 100, height: 50))
    }

    @Test func fitSizeWideBoxClampsToHeight() {
        // aspect 2, box 100×20: width-first gives height 50 > 20, so re-fit by height.
        #expect(Thumbnailer.fitSize(width: 200, height: 100, box: NSSize(width: 100, height: 20))
                == NSSize(width: 40, height: 20))
    }

    @Test func fitSizePortraitFitsHeight() {
        // aspect 0.5, box 50×100: height-first gives width 50 (== box.width), no re-fit.
        #expect(Thumbnailer.fitSize(width: 100, height: 200, box: NSSize(width: 50, height: 100))
                == NSSize(width: 50, height: 100))
    }

    @Test func fitSizeTallBoxClampsToWidth() {
        // aspect 0.5, box 20×100: height-first gives width 50 > 20, so re-fit by width.
        #expect(Thumbnailer.fitSize(width: 100, height: 200, box: NSSize(width: 20, height: 100))
                == NSSize(width: 20, height: 40))
    }

    @Test func fitSizeNeverUpscalesSmallSource() {
        #expect(Thumbnailer.fitSize(width: 10, height: 10, box: NSSize(width: 100, height: 100))
                == NSSize(width: 10, height: 10))
    }

    // MARK: displayScale

    @Test func displayScaleIsAtLeastOne() {
        #expect(Thumbnailer.displayScale() >= 1.0)
    }

    // MARK: thumbnail(for:fitting:) — cache + source selection

    @Test func thumbnailUsesStoredPNGForSmallBoxAndCaches() throws {
        let stored = try #require(Thumbnailer.makeThumbnailData(from: tiff(width: 400, height: 400)))
        let clip = ClipRecord(typeIdentifiers: ["TIFF"], thumbnailData: stored, contentHash: 100)
        let thumbnailer = Thumbnailer()
        let box = NSSize(width: 16, height: 16) // small ⇒ stays under storedMaxPixelSize
        let first = try #require(thumbnailer.thumbnail(for: clip, fitting: box))
        let second = try #require(thumbnailer.thumbnail(for: clip, fitting: box))
        #expect(first === second) // second call is a cache hit
    }

    @Test func thumbnailFallsBackToOriginalForLargeBox() throws {
        // A box big enough that neededPixels > storedMaxPixelSize forces use of
        // the original image bytes.
        let original = tiff(width: 800, height: 800)
        let clip = ClipRecord(typeIdentifiers: ["TIFF"], image: ClipImage(data: original), contentHash: 101)
        let thumbnailer = Thumbnailer()
        let box = NSSize(width: 400, height: 400)
        #expect(thumbnailer.thumbnail(for: clip, fitting: box) != nil)
    }

    @Test func thumbnailIsNilWhenClipHasNoImageData() {
        let clip = ClipRecord(typeIdentifiers: ["String"], stringValue: "text", contentHash: 102)
        let thumbnailer = Thumbnailer()
        #expect(thumbnailer.thumbnail(for: clip, fitting: NSSize(width: 16, height: 16)) == nil)
    }
}
