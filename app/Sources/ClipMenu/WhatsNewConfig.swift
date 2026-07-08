import Foundation
import DragonKit

/// ClipMenu's release notes for DragonKit's shared What's New pane. Update per
/// release alongside the CFBundleShortVersionString bump in Info.plist.
enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v\(AppInfo.version)",
            date: "2026-07-08",
            summary: L("Under-the-hood performance and reliability improvements."),
            sections: [
                ChangeSection(kind: .improved, entries: [
                    L("Lower background energy use — the clipboard watch now lets macOS batch its wake-ups."),
                    L("Faster history menu and clipboard capture, especially with a large history, thanks to database indexes and a lighter history trim."),
                    L("Snappier type-to-filter in the History menu."),
                ]),
                ChangeSection(kind: .fixed, entries: [
                    L("Copies from an excluded app are no longer recorded if you switch away before the clipboard is read."),
                    L("The shortcut recorder now tells you when a shortcut is already in use or unavailable, instead of only beeping."),
                ]),
            ]
        )
    }
}
