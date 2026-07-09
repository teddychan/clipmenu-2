import Foundation
import DragonKit

/// ClipMenu's release notes for DragonKit's shared What's New pane. Update per
/// release alongside the CFBundleShortVersionString bump in Info.plist.
enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v\(AppInfo.version)",
            date: "2026-07-10",
            summary: L("Fixes clipboard history no longer saving once it filled up."),
            sections: [
                ChangeSection(kind: .fixed, entries: [
                    L("Clipboard history stopped saving new copies once it reached your history-size limit. New copies are captured again, and the oldest item is trimmed as intended."),
                ]),
            ]
        )
    }
}
