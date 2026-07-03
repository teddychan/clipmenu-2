import Foundation
import DragonKit

/// ClipMenu's release notes for DragonKit's shared What's New pane. Update per
/// release alongside the CFBundleShortVersionString bump in Info.plist.
enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v\(AppInfo.version)",
            date: "2026-07-04",
            summary: L("ClipMenu now shares the Dragon apps' settings foundation."),
            sections: [
                ChangeSection(kind: .added, entries: [
                    L("A sidebar settings window shared with the other Dragon apps."),
                    L("Permissions, What's New, and Software Update panes."),
                    L("Switch language instantly — no restart needed."),
                ]),
                ChangeSection(kind: .changed, entries: [
                    L("Uninstall now confirms right inside Settings instead of a separate window."),
                ]),
            ]
        )
    }
}
