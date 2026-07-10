import Testing
import DragonKit
@testable import ClipMenu

// Characterization tests for the two static content providers that feed
// DragonKit's shared About and What's New panes. They are pure value builders,
// so the tests pin the exact links, credits, and release-note shape the app
// ships. Both are @MainActor because they call DragonKit's MainActor-isolated
// L()/DragonAbout helpers.

@MainActor
@Suite struct AboutConfigCoverageTests {

    @Test func contentSingleSourcesNameAndCopyright() {
        let content = AboutConfig.content
        #expect(content.appName == AppInfo.displayName)
        #expect(content.copyright == AppInfo.copyright)
        #expect(content.versionString == DragonAbout.versionString())
        #expect(!content.versionString.isEmpty)
    }

    @Test func contentHasWebsiteAndSupportLinks() {
        let links = AboutConfig.content.links
        #expect(links.count == 2)

        let website = links[0]
        #expect(website.detail == "dragonapp.com/clipmenu")
        #expect(website.systemImage == "globe")
        #expect(website.url.absoluteString == "https://www.dragonapp.com/clipmenu")

        let support = links[1]
        #expect(support.detail == "teddychan/clipmenu-2")
        #expect(support.systemImage == "lifepreserver")
        #expect(support.url.absoluteString == "https://github.com/teddychan/clipmenu-2/issues")
    }

    @Test func contentCreditsAuthorsAndLicense() {
        let credits = AboutConfig.content.credits
        #expect(credits.count == 3)
        #expect(credits.map(\.value) == ["Teddy Chan", "Naotaka Morimoto", "MIT"])
    }
}

@MainActor
@Suite struct WhatsNewConfigCoverageTests {

    @Test func versionIsPrefixedFromAppInfo() {
        #expect(WhatsNewConfig.content.version == "v\(AppInfo.version)")
    }

    @Test func contentHasDateAndSummary() {
        let content = WhatsNewConfig.content
        #expect(content.date == "2026-07-11")
        #expect(!content.summary.isEmpty)
    }

    @Test func contentHasASingleImprovedSection() {
        let sections = WhatsNewConfig.content.sections
        #expect(sections.count == 1)
        let section = try! #require(sections.first)
        #expect(section.kind == .improved)
        #expect(section.entries.count == 1)
        #expect(!(section.entries.first ?? "").isEmpty)
    }
}
