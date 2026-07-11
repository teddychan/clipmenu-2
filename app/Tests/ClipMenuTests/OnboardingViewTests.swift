import Testing
import SwiftUI
import ViewInspector
import DragonKit
@testable import ClipMenu

// SwiftUI-body coverage for the first-run setup wizard (`OnboardingView` and its
// private per-step subviews). The step subviews are `private struct`s, so they
// can't be constructed directly — instead we drive the whole wizard by writing
// the persisted `onboardingStep` index and inspecting the rendered tree, which
// exercises each step's body plus the shared footer / header / page-dot pieces.
//
// Plain `inspect()` is used (no `ViewHosting`): pages are selected by the
// `@AppStorage(onboardingStep)` index we set here, and every child step's own
// `@State`/`@AppStorage` renders from its default/stored value. Plain inspection
// also skips SwiftUI lifecycle, so `onAppear`/`onChange` side effects never fire.
//
// Two things are deliberately NOT asserted because they depend on the host
// machine's real Accessibility grant (`AXIsProcessTrusted()`, read at
// `OnboardingPermissions` init and not overridable): the permissions step's
// grant-state row (Granted / Not granted + grant buttons) and the permissions
// step's footer primary title (Skip vs Continue). The pure `primaryAction`
// decision behind that title is already covered in `OnboardingGateTests`.
//
// The suite is `.serialized` and `@MainActor`: `L(...)` is main-actor isolated,
// and every test writes `UserDefaults.standard` (restored via `defer`).
@MainActor
@Suite(.serialized) struct OnboardingViewTests {

    // MARK: Helpers

    /// Keys this suite writes; snapshot + restore so tests don't leak state.
    private static let touchedKeys = [
        PreferenceKeys.onboardingStep,
        PreferenceKeys.maxHistorySize,
    ]

    private func snapshot() -> [String: Any?] {
        var out: [String: Any?] = [:]
        for k in Self.touchedKeys { out[k] = UserDefaults.standard.object(forKey: k) }
        return out
    }

    private func restore(_ saved: [String: Any?]) {
        for (k, v) in saved {
            if let v { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
    }

    /// Build the wizard positioned on `step` (its persisted resume index).
    private func wizard(on step: OnboardingStep) -> OnboardingView {
        UserDefaults.standard.set(step.rawValue, forKey: PreferenceKeys.onboardingStep)
        return OnboardingView(permissions: OnboardingPermissions(), onFinish: {})
    }

    /// True if the rendered tree contains an `Image(systemName:)` with `name`.
    private func hasSymbol(_ view: OnboardingView, _ name: String) throws -> Bool {
        try view.inspect().findAll(ViewType.Image.self).contains {
            (try? $0.actualImage()) == Image(systemName: name)
        }
    }

    // MARK: Welcome (step 1)

    @Test func welcomeShowsIntroLanguagePickerAndFeatureRows() throws {
        let saved = snapshot(); defer { restore(saved) }
        let sut = wizard(on: .welcome)

        // App name is a literal (not localized) hero title.
        #expect(try sut.inspect().find(text: "ClipMenu").string() == "ClipMenu")
        _ = try sut.inspect().find(text: L("Your clipboard history and snippets, one keystroke away."))
        _ = try sut.inspect().find(text: L("Language"))

        // The three intro feature rows.
        _ = try sut.inspect().find(text: L("History at your fingertips"))
        _ = try sut.inspect().find(text: L("Snippets for what you reuse"))
        _ = try sut.inspect().find(text: L("Open it with a shortcut"))

        // Hero glyph + one of the feature glyphs.
        #expect(try hasSymbol(sut, "list.clipboard"))
        #expect(try hasSymbol(sut, "bookmark"))

        // Footer primary is a plain advance on the first step.
        _ = try sut.inspect().find(button: L("Continue"))
    }

    @Test func welcomeBackButtonIsDisabled() throws {
        let saved = snapshot(); defer { restore(saved) }
        let sut = wizard(on: .welcome)
        let back = try sut.inspect().find(button: L("Back"))
        #expect(try back.isDisabled())
    }

    // MARK: Permissions (step 2) — direct build (default test env has no sandbox)

    @Test func permissionsShowsAccessibilityHeaderAndHint() throws {
        let saved = snapshot(); defer { restore(saved) }
        let sut = wizard(on: .permissions)

        // Header + hint are shown regardless of the machine's grant state.
        _ = try sut.inspect().find(text: L("Accessibility (optional)"))
        _ = try sut.inspect().find(text: L("Lets ClipMenu paste the item you pick straight into the app you're using."))
        _ = try sut.inspect().find(text: L("Accessibility"))
        _ = try sut.inspect().find(text: L("You can skip this and turn it on later in Settings."))
        #expect(try hasSymbol(sut, "accessibility"))
    }

    // MARK: History (step 3)

    @Test func historyShowsTunableRowsAndKeepCount() throws {
        let saved = snapshot(); defer { restore(saved) }
        UserDefaults.standard.set(42, forKey: PreferenceKeys.maxHistorySize)
        let sut = wizard(on: .history)

        _ = try sut.inspect().find(text: L("History essentials"))
        _ = try sut.inspect().find(text: L("Tune what ClipMenu remembers. Change any of it later in Settings."))
        _ = try sut.inspect().find(text: L("Items to keep"))
        _ = try sut.inspect().find(text: L("Keep history after quitting"))
        _ = try sut.inspect().find(text: L("Store copied images"))
        // The @AppStorage-bound keep-count renders as a monospaced number.
        #expect(try sut.inspect().find(text: "42").string() == "42")
        #expect(try hasSymbol(sut, "clock.arrow.circlepath"))
    }

    // MARK: Features (step 4) — direct build shows the auto-paste row

    @Test func featuresShowsOptionsAndShortcutRows() throws {
        let saved = snapshot(); defer { restore(saved) }
        let sut = wizard(on: .features)

        _ = try sut.inspect().find(text: L("Make it yours"))
        _ = try sut.inspect().find(text: L("Turn on what you want now. Everything is in Settings later."))
        _ = try sut.inspect().find(text: L("Launch at login"))
        // Auto-paste row only exists on the direct build (the default test env).
        _ = try sut.inspect().find(text: L("Paste automatically after picking"))
        _ = try sut.inspect().find(text: L("Global shortcuts"))
        _ = try sut.inspect().find(text: L("History menu"))
        _ = try sut.inspect().find(text: L("Main menu"))
        _ = try sut.inspect().find(text: L("Snippets menu"))
        #expect(try hasSymbol(sut, "slider.horizontal.3"))
    }

    // MARK: Done (step 5)

    @Test func doneShowsCompletionShortcutAndFinishButton() throws {
        let saved = snapshot(); defer { restore(saved) }
        let sut = wizard(on: .done)

        _ = try sut.inspect().find(text: L("You're all set"))
        _ = try sut.inspect().find(text: L("ClipMenu is live in your menu bar."))
        _ = try sut.inspect().find(text: L("Open your clipboard history anytime."))
        // The paste-history key combo, rendered as three keycaps.
        _ = try sut.inspect().find(text: "⌘")
        _ = try sut.inspect().find(text: "⌃")
        _ = try sut.inspect().find(text: "V")
        #expect(try hasSymbol(sut, "checkmark.circle.fill"))
        // Last step's footer primary finishes the wizard.
        _ = try sut.inspect().find(button: L("Open ClipMenu"))
    }

    // MARK: Footer shared across steps

    @Test func footerPrimaryTitleForDeterministicSteps() throws {
        let saved = snapshot(); defer { restore(saved) }
        // Welcome / history / features all advance → "Continue".
        for step in [OnboardingStep.welcome, .history, .features] {
            let sut = wizard(on: step)
            #expect((try? sut.inspect().find(button: L("Continue"))) != nil)
        }
        // Done finishes → "Open ClipMenu".
        let done = wizard(on: .done)
        #expect((try? done.inspect().find(button: L("Open ClipMenu"))) != nil)
    }

    @Test func footerBackButtonEnabledPastWelcome() throws {
        let saved = snapshot(); defer { restore(saved) }
        let sut = wizard(on: .done)
        let back = try sut.inspect().find(button: L("Back"))
        #expect(try back.isDisabled() == false)
    }

    // MARK: Step model (OnboardingFlow) — ordering the page dots reflect

    @Test func stepEnumerationOrderAndCount() {
        // Five steps in fixed order; `rawValue` is the persisted resume index and
        // the active page-dot index the footer highlights.
        #expect(OnboardingStep.allCases.count == 5)
        #expect(OnboardingStep.allCases == [.welcome, .permissions, .history, .features, .done])
        #expect(OnboardingStep.welcome.rawValue == 0)
        #expect(OnboardingStep.done.rawValue == 4)
    }
}
