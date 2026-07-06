import Foundation
import DragonKit

/// ClipMenu's content for DragonKit's shared About pane. Layout is owned by
/// DragonKit (`AboutSettingsPane`); only the text/links here are the app's.
/// The version is single-sourced from Info.plist via `AppInfo` — never hardcoded.
enum AboutConfig {
    /// Primary link: the app's marketing page on dragonapp.com (not GitHub).
    private static let websiteURL = URL(string: "https://www.dragonapp.com/clipmenu")!
    /// Support link goes straight to the GitHub issues page.
    private static let issuesURL = URL(string: "https://github.com/teddychan/clipmenu-2/issues")!

    @MainActor
    static var content: AboutContent {
        AboutContent(
            appName: AppInfo.displayName,
            versionString: DragonAbout.versionString(),
            copyright: AppInfo.copyright,
            links: [
                AboutLink(title: L("Website"), detail: "dragonapp.com/clipmenu",
                          systemImage: "globe", url: websiteURL),
                AboutLink(title: L("Support on GitHub"), detail: "teddychan/clipmenu-2",
                          systemImage: "lifepreserver", url: issuesURL),
            ],
            credits: [
                (label: L("Created by"), value: "Teddy Chan"),
                (label: L("Original ClipMenu"), value: "Naotaka Morimoto"),
                (label: L("License"), value: "MIT"),
            ]
        )
    }
}
