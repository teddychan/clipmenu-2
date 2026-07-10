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
            summary: L("Fixes for clipboard history saving, excluded apps, and history speed."),
            sections: [
                ChangeSection(kind: .fixed, entries: [
                    L("Clipboard history stopped saving new copies once it reached your history-size limit. New copies are captured again, and the oldest item is trimmed as intended."),
                    L("The Exclude Applications list no longer drops a copy you make right after switching away from an excluded app — only copies made in an excluded app are skipped."),
                    L("Restored fast history lookups on installs that were upgraded, by rebuilding database indexes that the upgrade could leave off."),
                ]),
            ]
        )
    }
}
