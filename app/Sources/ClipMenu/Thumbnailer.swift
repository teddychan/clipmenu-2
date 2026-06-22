import AppKit
import ImageIO

// Downsampled image thumbnails for the menu. Maps to ARCHITECTURE.md `Thumbnailer`;
// legacy MenuController.m:828-846 (image vs icon) + Clip.m:350-441 (thumbnailOfSize:
// aspect-preserving, never upscale, cached by size).
//
// Per CLAUDE.md §4: never keep full-size images alive for the menu. At capture
// we store a small downsampled PNG thumbnail (makeThumbnailData) on the clip and
// the menu renders from that. The original TIFF lives in a separate row
// (ClipRecord.image / ClipImage) and is loaded only when pasted (§D row 69).
// Decoded thumbnails are cached (contentHash + box) like legacy's per-Clip cache.

@MainActor
final class Thumbnailer {
    /// Bounded decoded-thumbnail cache. Count-limited so it can't grow for the
    /// life of the process as clips churn through the history.
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    /// Longest side (px) of the stored thumbnail. Covers the default 100×32 menu
    /// box at 2× plus larger thumbnail prefs; a PNG at this size is a few tens of
    /// KB, vs. the multi-MB original.
    nonisolated static let storedMaxPixelSize = 256

    /// Thumbnail for a clip's image, fit into `box`, or nil if the clip has none.
    /// Renders from the small stored `thumbnailData` so the full `imageData` is
    /// never faulted into memory for the menu (CLAUDE.md §4).
    func thumbnail(for clip: ClipRecord, fitting box: NSSize) -> NSImage? {
        guard let data = clip.thumbnailData else { return nil }
        let key = "\(clip.contentHash)-\(Int(box.width))x\(Int(box.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.makeThumbnail(from: data, fitting: box) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Downsampled PNG thumbnail bytes for storage, derived from full image data
    /// (e.g. a captured TIFF). Returns nil if the data can't be decoded. Runs off
    /// the main actor at capture; the original bytes are stored separately and
    /// untouched (paste fidelity).
    nonisolated static func makeThumbnailData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: storedMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Decode a downsampled thumbnail (longest side ≤ the box's larger dimension)
    /// and present it at the aspect-fit display size (never upscaled).
    nonisolated static func makeThumbnail(from data: Data, fitting box: NSSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth > 0, pixelHeight > 0
        else { return nil }

        let maxPixelSize = Int(max(box.width, box.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let displaySize = fitSize(width: pixelWidth, height: pixelHeight, box: box)
        return NSImage(cgImage: cgImage, size: displaySize)
    }

    /// Aspect-fit `width`×`height` into `box`, never upscaling (Clip.m:387-413).
    nonisolated static func fitSize(width: Double, height: Double, box: NSSize) -> NSSize {
        let aspect = width / height
        var newWidth: Double
        var newHeight: Double

        if aspect >= 1 {
            newWidth = box.width
            newHeight = newWidth / aspect
            if newHeight > box.height {
                newHeight = box.height
                newWidth = box.height * aspect
            }
        } else {
            newHeight = box.height
            newWidth = box.height * aspect
            if newWidth > box.width {
                newWidth = box.width
                newHeight = box.width / aspect
            }
        }

        // Don't upscale beyond the original (Clip.m:407-413).
        if newWidth > width { newWidth = width }
        if newHeight > height { newHeight = height }

        return NSSize(width: newWidth, height: newHeight)
    }
}
