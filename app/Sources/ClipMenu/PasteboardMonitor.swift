import AppKit

// Stub clipboard watcher. Maps to ARCHITECTURE.md §2 `ClipboardMonitor`
// (legacy ClipsController polling, ClipsController.m:587-649, 815-833).
//
// Design per CLAUDE.md performance guardrails: the pasteboard has no change
// notification, so poll `NSPasteboard.general.changeCount` on a coalesced
// timer. This monitor is an `actor`, so its loop — including the changeCount
// read AND the payload snapshot — runs OFF the main actor; copying a multi-MB
// image/PDF never stalls the UI (CLAUDE.md §3). NSPasteboard is obtained and
// used entirely on this actor's executor (see PasteboardReader).
//
// On a changeCount change it reads a snapshot and hands it to the ClipStore
// actor to persist. Default interval 0.75s with a 1.0s cap mirrors SPEC §4
// (timeInterval / MAX_TIME_INTERVAL). Per-app exclusion
// (ClipsController.m:606-608) is applied inside PasteboardReader.snapshot()
// (returns nil for excluded front apps).

actor PasteboardMonitor {
    private var lastChangeCount: Int = 0
    private var pollTask: Task<Void, Never>?
    private var clipStore: ClipStore?

    /// Polling interval bounds: clamped to the legacy maximum of 1.0s, and to a
    /// 0.25s floor so the slider's 0 value can't turn the poll into a busy loop.
    static let maxInterval: Duration = .seconds(1)
    static let minInterval: Duration = .milliseconds(250)
    static let defaultInterval: Duration = .milliseconds(750)

    /// The poll interval to use given the stored `timeInterval` preference (in
    /// seconds), or nil when unset. Clamped to [minInterval, maxInterval]; nil
    /// → defaultInterval. Pure, so it is unit-testable.
    static func effectiveInterval(fromSeconds seconds: Double?) -> Duration {
        guard let seconds else { return defaultInterval }
        let requested = Duration.seconds(seconds)
        return min(max(requested, minInterval), maxInterval)
    }

    func start(clipStore: ClipStore, interval: Duration? = nil) async {
        guard pollTask == nil else { return }
        self.clipStore = clipStore
        let effective = interval ?? Self.effectiveInterval(
            fromSeconds: UserDefaults.standard.object(forKey: PreferenceKeys.timeInterval) as? Double)

        lastChangeCount = NSPasteboard.general.changeCount

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: effective)
                await self?.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // Read and persist off the main actor (ClipsController.m:610-643).
        guard let snapshot = PasteboardReader.snapshot() else { return }
        await clipStore?.capture(snapshot)
    }
}
