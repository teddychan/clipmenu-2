import SwiftUI

// The first-run setup wizard UI (dark, centered-card style). Hosted in a plain
// NSWindow by `OnboardingWindowController`; the flow's only persisted state is the
// `onboardingStep` index, so a relaunch mid-wizard (e.g. a language change)
// rebuilds straight onto the same step. Pure decisions live in `OnboardingGate`
// (OnboardingFlow.swift); this file is presentation + live preference binding.

// MARK: - Palette

/// Fixed dark palette so the wizard looks identical regardless of system
/// appearance (the window forces dark). Brand accent is ClipMenu's `#1f6fd6`.
private enum OB {
    static let windowBG = Color(red: 0x1b / 255, green: 0x1b / 255, blue: 0x1d / 255)
    static let heroBG   = Color(red: 0x0d / 255, green: 0x0d / 255, blue: 0x0f / 255)
    static let card     = Color(red: 0x25 / 255, green: 0x25 / 255, blue: 0x27 / 255)
    static let divider  = Color(red: 0x37 / 255, green: 0x37 / 255, blue: 0x3a / 255)
    static let keycap   = Color(red: 0x3a / 255, green: 0x3a / 255, blue: 0x3c / 255)
    static let accent   = Color(red: 0x1f / 255, green: 0x6f / 255, blue: 0xd6 / 255)
    static let subtitle = Color(red: 0x9b / 255, green: 0x9b / 255, blue: 0x9f / 255)
    static let hint     = Color(red: 0x8a / 255, green: 0x8a / 255, blue: 0x8e / 255)
}

// MARK: - Shared pieces

/// Rounded black icon tile with a white SF Symbol, like Vorssaint's step glyph.
private struct IconTile: View {
    let symbol: String
    var color: Color = .white
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black)
            .frame(width: 58, height: 58)
            .overlay(Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(color))
    }
}

/// A single keyboard cap, e.g. ⌘.
private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(OB.keycap))
    }
}

/// Header used by every step except the welcome hero: icon tile + title + subtitle.
private struct StepHeader: View {
    let symbol: String
    var symbolColor: Color = .white
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            IconTile(symbol: symbol, color: symbolColor)
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 14)).foregroundStyle(OB.subtitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
    }
}

/// Grouped dark "card" container (one section of rows).
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(OB.card))
    }
}

// MARK: - Root

struct OnboardingView: View {
    @AppStorage(PreferenceKeys.onboardingStep) private var index = 0
    @ObservedObject var permissions: OnboardingPermissions
    /// Reached the end / user dismissed → mark complete and close.
    let onFinish: () -> Void
    /// Language changed → relaunch to apply, resuming on the same step.
    let onLanguageChange: () -> Void

    private var steps: [OnboardingStep] { OnboardingStep.allCases }
    private var current: OnboardingStep { OnboardingGate.resumeStep(savedIndex: index) }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(OB.divider).frame(height: 0.5)
            footer
        }
        .frame(width: 560, height: 620)
        .background(OB.windowBG)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if !steps.indices.contains(index) { index = 0 }
        }
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .welcome:     WelcomeStep(onLanguageChange: onLanguageChange)
        case .permissions: PermissionsStep(permissions: permissions)
        case .history:     HistoryStep()
        case .features:    FeaturesStep()
        case .done:        DoneStep()
        }
    }

    // MARK: Footer (Back · page dots · primary) — pinned, shared across steps.

    private var footer: some View {
        HStack {
            Button(L("Back")) { withAnimation(.easeInOut(duration: 0.2)) { index = max(0, index - 1) } }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .foregroundStyle(current == .welcome ? Color(white: 0.36) : Color(white: 0.82))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(current == .welcome ? .clear : Color(white: 0.27), lineWidth: 0.5))
                .disabled(current == .welcome)

            Spacer()
            PageDots(count: steps.count, active: current.rawValue)
            Spacer()

            Button(primaryTitle) { primaryTap() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(OB.accent))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var primaryTitle: String {
        switch OnboardingGate.primaryAction(
            step: current, channel: DistributionChannel.current,
            accessibilityGranted: permissions.accessibility) {
        case .advance: return L("Continue")
        case .skip:    return L("Skip this step")
        case .finish:  return L("Open ClipMenu")
        }
    }

    private func primaryTap() {
        if current == .done { onFinish(); return }
        withAnimation(.easeInOut(duration: 0.2)) { index = min(steps.count - 1, index + 1) }
    }
}

/// Capsule page indicator; the active dot widens, like Vorssaint.
private struct PageDots: View {
    let count: Int
    let active: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { i in
                Capsule()
                    .fill(i == active ? OB.accent : Color(white: 0.23))
                    .frame(width: i == active ? 18 : 6, height: 6)
            }
        }
    }
}

// MARK: - Step 1: Welcome & language

private struct WelcomeStep: View {
    @AppStorage(PreferenceKeys.appLanguage) private var appLanguage = "en"
    let onLanguageChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                IconTile(symbol: "list.clipboard")
                Text("ClipMenu").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                Text(L("Your clipboard history and snippets, one keystroke away."))
                    .font(.system(size: 14)).foregroundStyle(OB.subtitle)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30).padding(.bottom, 26)
            .background(OB.heroBG)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text(L("Language")).foregroundStyle(.white)
                    Picker("", selection: $appLanguage) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("Français").tag("fr")
                        Text("日本語").tag("ja")
                        Text("한국어").tag("ko")
                        Text("简体中文").tag("zh-Hans")
                        Text("繁體中文").tag("zh-Hant")
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: appLanguage) { _, newValue in
                        // Apply immediately: L() is resolved once per process, so re-render
                        // the rest of the wizard in the chosen language by relaunching. The
                        // saved step makes it resume here. Mirror to the OS override too.
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                        onLanguageChange()
                    }
                }
                feature("clock.arrow.circlepath", L("History at your fingertips"),
                        L("Everything you copy, ready to paste from the menu bar."))
                feature("bookmark", L("Snippets for what you reuse"),
                        L("Save boilerplate text and paste it instantly."))
                feature("keyboard", L("Open it with a shortcut"),
                        L("Pop up your history anywhere, pick an item, done."))
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            Spacer(minLength: 0)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black).frame(width: 34, height: 34)
                .overlay(Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(OB.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 2: Permissions (build-aware)

private struct PermissionsStep: View {
    @ObservedObject var permissions: OnboardingPermissions
    private var isAppStore: Bool { DistributionChannel.current == .appStore }

    var body: some View {
        VStack(spacing: 20) {
            if isAppStore {
                StepHeader(symbol: "checkmark.shield",
                           title: L("No permissions needed"),
                           subtitle: L("ClipMenu works the moment you continue."))
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Your clipboard stays on this Mac"))
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                            Text(L("History is stored locally. Nothing is uploaded or sent anywhere."))
                                .font(.system(size: 13)).foregroundStyle(OB.subtitle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(15)
                }
                Text(L("iCloud sync is optional and off until you turn it on in Settings."))
                    .font(.system(size: 12)).foregroundStyle(OB.hint)
                    .multilineTextAlignment(.center)
            } else {
                StepHeader(symbol: "accessibility",
                           title: L("Accessibility (optional)"),
                           subtitle: L("Lets ClipMenu paste the item you pick straight into the app you're using."))
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(permissions.accessibility ? .green : .orange)
                        Text(L("Accessibility")).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                        Spacer()
                        Text(permissions.accessibility ? L("Granted") : L("Not granted"))
                            .font(.system(size: 13))
                            .foregroundStyle(permissions.accessibility ? .green : .orange)
                    }
                    .padding(15)
                    if !permissions.accessibility {
                        Rectangle().fill(OB.divider).frame(height: 0.5)
                        HStack(spacing: 10) {
                            secondaryButton(L("Grant access")) { permissions.requestAccessibility() }
                            secondaryButton(L("Open System Settings…")) { permissions.openAccessibilitySettings() }
                            Spacer()
                        }
                        .padding(15)
                    }
                }
                Text(L("You can skip this and turn it on later in Settings."))
                    .font(.system(size: 12)).foregroundStyle(OB.hint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 24)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(OB.keycap))
    }
}

// MARK: - Step 3: History essentials

private struct HistoryStep: View {
    @AppStorage(PreferenceKeys.maxHistorySize) private var maxHistorySize = 20
    @AppStorage(PreferenceKeys.saveHistoryOnQuit) private var saveOnQuit = true
    @State private var storeImages = true

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(symbol: "clock.arrow.circlepath",
                       title: L("History essentials"),
                       subtitle: L("Tune what ClipMenu remembers. Change any of it later in Settings."))
            Card {
                row {
                    labelStack(L("Items to keep"), L("Oldest are dropped past this count."))
                    Spacer()
                    Text("\(maxHistorySize)").foregroundStyle(.white).monospacedDigit()
                    Stepper("", value: $maxHistorySize, in: 1 ... 999).labelsHidden()
                }
                divider
                row {
                    Text(L("Keep history after quitting")).foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $saveOnQuit).labelsHidden().tint(OB.accent)
                }
                divider
                row {
                    labelStack(L("Store copied images"), L("Kept as small thumbnails."))
                    Spacer()
                    Toggle("", isOn: $storeImages).labelsHidden().tint(OB.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 24)
        .onAppear {
            let saved = UserDefaults.standard.dictionary(forKey: PreferenceKeys.storeTypes) as? [String: Bool] ?? [:]
            storeImages = saved["TIFF"] ?? true
        }
        .onChange(of: storeImages) { _, newValue in
            var dict = UserDefaults.standard.dictionary(forKey: PreferenceKeys.storeTypes) as? [String: Bool] ?? [:]
            dict["TIFF"] = newValue
            UserDefaults.standard.set(dict, forKey: PreferenceKeys.storeTypes)
        }
    }

    private var divider: some View { Rectangle().fill(OB.divider).frame(height: 0.5) }
    private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack { content() }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private func labelStack(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(OB.hint)
        }
    }
}

// MARK: - Step 4: Make it yours (optional features + shortcuts)

private struct FeaturesStep: View {
    @AppStorage(PreferenceKeys.loginItem) private var loginItem = false
    @AppStorage(PreferenceKeys.inputPasteCommand) private var inputPasteCommand = true
    private var isDirect: Bool { DistributionChannel.current == .direct }

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(symbol: "slider.horizontal.3",
                       title: L("Make it yours"),
                       subtitle: L("Turn on what you want now. Everything is in Settings later."))
            Card {
                checkRow(isOn: $loginItem) {
                    Text(L("Launch at login")).foregroundStyle(.white)
                }
                if isDirect {
                    divider
                    checkRow(isOn: $inputPasteCommand) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Paste automatically after picking")).foregroundStyle(.white)
                            Text(L("ClipMenu presses ⌘V for you.")).font(.system(size: 12)).foregroundStyle(OB.hint)
                        }
                    }
                }
            }
            Text(L("Global shortcuts")).font(.system(size: 12)).foregroundStyle(OB.hint)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
            Card {
                shortcutRow(L("History menu"), .history)
                divider
                shortcutRow(L("Main menu"), .main)
                divider
                shortcutRow(L("Snippets menu"), .snippets)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 24)
        .onChange(of: loginItem) { _, newValue in LoginItem.setEnabled(newValue) }
    }

    private var divider: some View { Rectangle().fill(OB.divider).frame(height: 0.5) }

    private func checkRow<C: View>(isOn: Binding<Bool>, @ViewBuilder _ label: () -> C) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn.wrappedValue ? OB.accent : OB.keycap)
                    .frame(width: 20, height: 20)
                    .overlay(isOn.wrappedValue ? Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) : nil)
                label()
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortcutRow(_ title: String, _ hotKey: MainMenuController.MenuHotKey) -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            ShortcutRecorder(hotKey: hotKey).frame(width: 130, height: 24)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

// MARK: - Step 5: You're all set

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 20) {
            StepHeader(symbol: "checkmark.circle.fill", symbolColor: .green,
                       title: L("You're all set"),
                       subtitle: L("ClipMenu is live in your menu bar."))
            Card {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        KeyCap(text: "⌘"); KeyCap(text: "⌃"); KeyCap(text: "V")
                    }
                    Text(L("Open your clipboard history anytime."))
                        .font(.system(size: 14)).foregroundStyle(Color(white: 0.82))
                    Text(L("You can also click the ClipMenu icon in the menu bar."))
                        .font(.system(size: 13)).foregroundStyle(OB.hint)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 24)
    }
}
