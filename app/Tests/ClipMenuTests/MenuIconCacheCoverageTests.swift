import Testing
import AppKit
@testable import ClipMenu

// Characterization tests for MenuIconCache: lazy build + identity caching per
// icon, and the size-driven cache invalidation (rebuild only when menuIconSize
// changes). NSImage / NSWorkspace.icon(for:) / SF Symbol construction all run
// fine headlessly. Serialized + save/restore because it reads
// UserDefaults.standard(menuIconSize).
@Suite(.serialized) @MainActor
struct MenuIconCacheCoverageTests {

    private func withIconSize(_ size: Int?, _ body: () -> Void) {
        let key = PreferenceKeys.menuIconSize
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        if let size { UserDefaults.standard.set(size, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        body()
    }

    @Test func allFourIconsBuildAtTheConfiguredSize() {
        withIconSize(20) {
            let cache = MenuIconCache()
            for icon in [cache.folderIcon, cache.snippetIcon, cache.actionIcon, cache.javaScriptIcon] {
                #expect(icon.size == NSSize(width: 20, height: 20))
            }
        }
    }

    @Test func repeatedAccessReturnsTheCachedInstance() {
        withIconSize(16) {
            let cache = MenuIconCache()
            #expect(cache.folderIcon === cache.folderIcon)
            #expect(cache.snippetIcon === cache.snippetIcon)
            #expect(cache.actionIcon === cache.actionIcon)
            #expect(cache.javaScriptIcon === cache.javaScriptIcon)
        }
    }

    @Test func defaultsToSixteenWhenNoPreferenceStored() {
        withIconSize(nil) {
            let cache = MenuIconCache()
            #expect(cache.folderIcon.size == NSSize(width: 16, height: 16))
        }
    }

    @Test func changingSizeRebuildsIcons() {
        let key = PreferenceKeys.menuIconSize
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let cache = MenuIconCache()
        UserDefaults.standard.set(18, forKey: key)
        let first = cache.folderIcon
        #expect(first.size == NSSize(width: 18, height: 18))

        UserDefaults.standard.set(28, forKey: key)
        let second = cache.folderIcon
        #expect(second.size == NSSize(width: 28, height: 28))
        // A size change invalidates the cache, so a fresh instance is built.
        #expect(first !== second)
    }
}
