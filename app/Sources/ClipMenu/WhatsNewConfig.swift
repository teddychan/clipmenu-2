import Foundation
import DragonKit

/// ClipMenu's release notes for DragonKit's shared What's New pane. Update per
/// release alongside the CFBundleShortVersionString bump in Info.plist.
enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v\(AppInfo.version)",
            date: "2026-07-11",
            summary: L("Faster clipboard history search."),
            sections: [
                ChangeSection(kind: .improved, entries: [
                    L("Searching your clipboard history (⌃⌘V) is faster — matching now happens in the database as you type instead of scanning every item, which keeps search quick even with a large history."),
                ]),
            ]
        )
    }
}
