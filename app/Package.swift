// swift-tools-version: 6.0
import PackageDescription
import Foundation

// ClipMenu — modern rewrite (scaffold).
// Built as a SwiftPM executable so it compiles with the Command Line Tools
// toolchain (no full Xcode required). Agent / menu-bar behavior is established
// at runtime via NSApp.setActivationPolicy(.accessory); the bundled .app uses
// the LSUIElement Info.plist at app/Info.plist (SwiftPM forbids Info.plist as
// a target resource, so it lives outside Sources and is applied when the .app
// bundle / Xcode project is produced later).
//
// Sparkle 2 (auto-update) is the one justified external dependency, and it is
// compiled in ONLY for the direct / Developer ID build. The Mac App Store build
// must not contain a self-updater (App Store policy + sandbox), so Sparkle is
// excluded at the manifest level: the dependency, the `SPARKLE` compile flag,
// and the framework-embedding rpath are added only when the build sets
// CLIPMENU_SPARKLE=1 (scripts/run.sh and .github/workflows/release.yml do;
// scripts/build-appstore.sh does not). With the flag off nothing links Sparkle,
// so the default / MAS / test builds stay Sparkle-free and resolve offline.
let sparkleEnabled = ProcessInfo.processInfo.environment["CLIPMENU_SPARKLE"] == "1"

var packageDependencies: [Package.Dependency] = []
var clipMenuDependencies: [Target.Dependency] = []
var clipMenuSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
var clipMenuLinkerSettings: [LinkerSetting] = []

if sparkleEnabled {
    packageDependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"))
    clipMenuDependencies.append(.product(name: "Sparkle", package: "Sparkle"))
    clipMenuSwiftSettings.append(.define("SPARKLE"))
    // Sparkle.framework is embedded in Contents/Frameworks by the bundle-assembly
    // step; this rpath lets the executable find it at runtime. Passed via -Xlinker
    // because SwiftPM linkerSettings flags go through the Swift driver, not clang.
    clipMenuLinkerSettings.append(.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]))
}

// iCloud sync & backup (Sources/ClipMenu/Premium/) is compiled into every build —
// the app is free on all channels, and iCloud sync is a free feature. It only goes
// live when the build carries iCloud entitlements + an embedded provisioning profile
// (and the CloudKit schema is deployed); otherwise `AppStore.makeContainer` falls
// back to a local store, so dev/unsigned builds still run.
var clipMenuTestSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "ClipMenu",
    // Base development language; localized .lproj resources live alongside
    // (Resources/<lang>.lproj/Localizable.strings) and fall back to English.
    defaultLocalization: "en",
    platforms: [
        // Apple Silicon only. macOS 26 doesn't run on Intel Macs (Apple dropped
        // x86_64 after macOS 15), so ClipMenu ships a single arm64 slice — there
        // is no universal/Intel build. The build scripts and CI pass
        // `--arch arm64` to enforce this explicitly (run.sh, build-appstore.sh,
        // .github/workflows/release.yml).
        .macOS("26.0") // latest macOS (SDK 26.x); see CLAUDE.md
    ],
    dependencies: packageDependencies,
    targets: [
        .executableTarget(
            name: "ClipMenu",
            dependencies: clipMenuDependencies,
            path: "Sources/ClipMenu",
            resources: [
                // Bundled JS actions + libraries (legacy resource/script tree),
                // run verbatim by JSActionRunner for transform parity (OQ#3).
                .copy("Resources/script"),
                // Menu-bar status icon: a vector PDF template (Apple-recommended
                // for status items — stays crisp at any size), rendered at 18pt
                // by StatusItemController.
                .copy("Resources/MenuBarIcon.pdf"),
                // UI string translations (issue #19). Each .lproj is processed so
                // SwiftPM compiles it into the resource bundle under its locale.
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj")
            ],
            swiftSettings: clipMenuSwiftSettings,
            linkerSettings: clipMenuLinkerSettings
        ),
        .testTarget(
            name: "ClipMenuTests",
            dependencies: ["ClipMenu"],
            path: "Tests/ClipMenuTests",
            swiftSettings: clipMenuTestSwiftSettings
        )
    ]
)
