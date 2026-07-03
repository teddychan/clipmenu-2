import Foundation

/// Central registry of `UserDefaults` / `@AppStorage` keys, so a key is spelled
/// in exactly one place. Referencing a constant is compiler-checked, which
/// catches the silent "typo creates a brand-new key" class of bug that bare
/// string literals invite.
///
/// Each constant's identifier is deliberately identical to its string value, so
/// the mapping is obvious at every call site. Keys are grouped by the Settings
/// tab they belong to, mirroring `SettingsSync.syncedKeys`.
enum PreferenceKeys {
    // General
    static let appLanguage = "appLanguage"
    static let inputPasteCommand = "inputPasteCommand"
    static let reorderClipsAfterPasting = "reorderClipsAfterPasting"
    static let maxHistorySize = "maxHistorySize"
    static let timeInterval = "timeInterval"
    static let saveHistoryOnQuit = "saveHistoryOnQuit"
    static let showStatusItem = "showStatusItem"
    static let exportHistoryAsSingleFile = "exportHistoryAsSingleFile"
    static let tagOfSeparatorForExportHistoryToFile = "tagOfSeparatorForExportHistoryToFile"

    // Menu
    static let numberOfItemsPlaceInline = "numberOfItemsPlaceInline"
    static let numberOfItemsPlaceInsideFolder = "numberOfItemsPlaceInsideFolder"
    static let maxMenuItemTitleLength = "maxMenuItemTitleLength"
    static let menuItemsAreMarkedWithNumbers = "menuItemsAreMarkedWithNumbers"
    static let addNumericKeyEquivalents = "addNumericKeyEquivalents"
    static let showLabelsInMenu = "showLabelsInMenu"
    static let addClearHistoryMenuItem = "addClearHistoryMenuItem"
    static let showAlertBeforeClearHistory = "showAlertBeforeClearHistory"
    static let showToolTipOnMenuItem = "showToolTipOnMenuItem"
    static let maxLengthOfToolTipKey = "maxLengthOfToolTipKey"
    static let changeFontSize = "changeFontSize"
    static let howToChangeFontSize = "howToChangeFontSize"
    static let selectedFontSize = "selectedFontSize"
    static let showImageInTheMenu = "showImageInTheMenu"
    /// Longest side (px) the image thumbnail is fit into in the menu; the user
    /// picks how big thumbnails are. Aspect-preserving, never upscaled, clamped
    /// to 16…256 (256 = the stored thumbnail's resolution, Thumbnailer).
    /// Replaces the legacy separate `thumbnailWidth`/`thumbnailHeight` box.
    static let thumbnailMaxSize = "thumbnailMaxSize"
    static let showIconInTheMenu = "showIconInTheMenu"
    static let menuIconSize = "menuIconSize"
    static let positionOfSnippets = "positionOfSnippets"
    static let groupSnippetsInFolder = "groupSnippetsInFolder"

    // Type
    static let storeTypes = "storeTypes"

    // Action
    static let enableAction = "enableAction"
    static let invokeActionImmediately = "invokeActionImmediately"
    static let controlClickBehavior = "controlClickBehavior"
    static let shiftClickBehavior = "shiftClickBehavior"
    static let optionClickBehavior = "optionClickBehavior"
    static let commandClickBehavior = "commandClickBehavior"

    // Shortcuts + exclusions
    static let hotKeys = "hotKeys"
    static let excludeApps = "excludeApps"

    // Machine-local (intentionally NOT synced across Macs).
    static let loginItem = "loginItem"
    static let suppressAlertForLoginItem = "suppressAlertForLoginItem"
    /// Security-scoped bookmark (Data) of the user-chosen backup folder, and a
    /// display path for the UI. The folder can live in Dropbox / iCloud Drive /
    /// Google Drive to sync backups across Macs (no iCloud entitlement needed).
    static let backupFolderBookmark = "backupFolderBookmark"
    static let backupFolderPath = "backupFolderPath"
    /// Whether to back up automatically when quitting (default true).
    static let automaticBackupEnabled = "automaticBackupEnabled"
    /// Last-selected Settings tab, so reopening Settings returns to it. The
    /// "About <App>" menu item overrides this to the About tab.
    static let settingsSelectedTab = "settingsSelectedTab"
    /// Local cache of the last snippet-backup time (a `Date`). NOT authoritative —
    /// the backup folder is the source of truth; this is an offline/perf fallback.
    static let lastSnippetBackupDate = "lastSnippetBackupDate"
    /// Local cache of the last snippet-backup content hash (offline fallback only).
    static let lastSnippetBackupHash = "lastSnippetBackupHash"

    /// First-run setup wizard. `onboardingCompleted` gates *whether* the wizard
    /// shows (set once it's finished or deliberately closed); `onboardingStep` is
    /// the resume point (the current step index), written on every Back/Continue so
    /// a mid-wizard relaunch — e.g. a language change — reopens on the same step.
    /// Per-device, so not synced.
    static let onboardingCompleted = "onboardingCompleted"
    static let onboardingStep = "onboardingStep"
}
