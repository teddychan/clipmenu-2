import Foundation

/// Localized UI string lookup (issue #19).
///
/// Resolves `key` against the `Localizable.strings` that ships in
/// `AppResources.bundle` — the SwiftPM resource bundle (`ClipMenu_ClipMenu.bundle`),
/// which holds the `.lproj` translations both under `swift build` (`Bundle.module`)
/// and in the packaged `.app` (copied into `Contents/Resources`).
///
/// Why not `bundle.localizedString(...)` or SwiftUI's automatic `LocalizedStringKey`:
/// both resolve a *secondary* resource bundle against its development region
/// (English) rather than the user's preferred language, so they always returned
/// the English value here. Instead we pick the best-matching shipped localization
/// ourselves and read that language's strings file directly. The English source
/// string is the key, so a missing translation falls back to readable English.
///
/// The language comes from the `appLanguage` preference set by the Language picker
/// in General settings (hard default English when unset), not from
/// `Locale.preferredLanguages` — so the in-app choice wins over the system language.
///
/// The table is resolved once (the chosen language is fixed for the process, as is
/// standard — changing the language requires an app relaunch) and the parsed
/// dictionary is immutable, so `L(_:)` is safe to call from any actor.
private enum Localization {
    static let table: [String: String] = {
        let bundle = AppResources.bundle
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        let language = Bundle.preferredLocalizations(
            from: bundle.localizations, forPreferences: [stored]).first ?? "en"
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings",
                                     inDirectory: nil, forLocalization: language),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else { return [:] }
        return dict
    }()
}

/// Returns the translation of `key` for the user's language, or `key` itself
/// (the English source) when no translation exists.
func L(_ key: String) -> String {
    Localization.table[key] ?? key
}
