import Foundation

/// Locates the bundled resource bundle (JS action scripts + the menu-bar icon).
///
/// In a packaged `.app` the resource bundle is copied into `Contents/Resources`
/// (the only location a `.app` can hold it without breaking code signing). For
/// `swift build` / `swift test` runs there is no `.app`, so we fall back to
/// SwiftPM's generated `Bundle.module`, which resolves via the build path.
enum AppResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ClipMenu_ClipMenu.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}
