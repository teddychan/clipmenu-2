import Foundation
import DragonKit

/// ClipMenu's release notes for DragonKit's shared What's New pane. Update per
/// release alongside the CFBundleShortVersionString bump in Info.plist.
enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v\(AppInfo.version)",
            date: "2026-07-05",
            summary: L("ClipMenu's Settings now line up with the other Dragon apps."),
            sections: [
                ChangeSection(kind: .changed, entries: [
                    L("Settings sidebar reordered to match the other Dragon apps: What's New now sits just before Software Update, and Sync & Backup follows Permissions."),
                ]),
            ]
        )
    }
}
