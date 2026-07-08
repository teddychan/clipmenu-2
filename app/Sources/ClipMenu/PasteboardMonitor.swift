import AppKit

// Clipboard watcher (legacy ClipsController polling, ClipsController.m:587-649,
// 815-833).
//
// Design per CLAUDE.md performance guardrails: the pasteboard has no change
// notification, so poll `NSPasteboard.general.changeCount` on a coalesced
// timer. This monitor is an `actor`, so its loop — including the changeCount
// read AND the payload snapshot — runs OFF the main actor; copying a multi-MB
// image/PDF never stalls the UI (CLAUDE.md §3). NSPasteboard is obtained and
// used entirely on this actor's executor (see PasteboardReader).
//
// On a changeCount change it reads a snapshot and hands it to the ClipStore
// actor to persist. Default interval 0.75s with a 1.0s cap mirrors the legacy
// timeInterval / MAX_TIME_INTERVAL. Per-app exclusion
// (ClipsController.m:606-608) is applied inside PasteboardReader.snapshot()
// (returns nil for excluded front apps).

actor PasteboardMonitor {
    private var lastChangeCount: Int = 0
    private var pollTask: Task<Void, Never>?
    private var clipStore: ClipStore?
    /// The frontmost app's bundle id observed at the PREVIOUS poll tick. Used to
    /// close the copy-then-switch exclusion race: a copy is detected up to one
    /// interval after it happened, by which time the user may have switched away
    /// from an excluded app, so the current frontmost no longer reveals the
    /// origin. If the app frontmost just before the change is excluded, we skip
    /// — erring toward not recording (privacy-safe). See ClipCapture.isExcluded.
    private var previousFrontBundleID: String?

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

    /// Wake-up tolerance for the poll timer: a quarter of the interval. Letting the
    /// OS defer each wake up to this much lets it coalesce our recurring wake with
    /// other timers, cutting the number of distinct wake events (and so the energy
    /// cost) of an always-on agent — without changing the nominal cadence. Capture
    /// latency stays bounded by interval + tolerance (≤ ~0.94s at the default).
    /// Pure, so it is unit-testable.
    static func pollTolerance(for interval: Duration) -> Duration {
        interval / 4
    }

    func start(clipStore: ClipStore, interval: Duration? = nil) async {
        guard pollTask == nil else { return }
        self.clipStore = clipStore
        let effective = interval ?? Self.effectiveInterval(
            fromSeconds: UserDefaults.standard.object(forKey: PreferenceKeys.timeInterval) as? Double)

        lastChangeCount = NSPasteboard.general.changeCount

        let tolerance = Self.pollTolerance(for: effective)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: effective, tolerance: tolerance)
                await self?.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        // Sample the frontmost app every tick so `previousFrontBundleID` holds the
        // app that was frontmost just BEFORE this one — the likely origin of a copy
        // detected this tick. Update it before every early return.
        let front = PasteboardReader.currentFrontBundleID()
        let previousFront = previousFrontBundleID
        previousFrontBundleID = front

        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // Copy-then-switch guard: if the app frontmost immediately before this
        // change is excluded, the copy most likely came from it even though the
        // user has since switched away — skip. PasteboardReader.snapshot() still
        // applies the current-front exclusion and the privacy markers.
        if PasteboardReader.isExcluded(previousFront, in: PasteboardReader.excludedBundleIdentifiers()) {
            return
        }

        // Read and persist off the main actor (ClipsController.m:610-643).
        guard let snapshot = PasteboardReader.snapshot() else { return }
        await clipStore?.capture(snapshot)
    }
}
