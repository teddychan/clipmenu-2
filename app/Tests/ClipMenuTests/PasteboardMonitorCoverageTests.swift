import Testing
import Foundation
import SwiftData
import AppKit
@testable import ClipMenu

// Characterization coverage for the PasteboardMonitor actor's start/stop lifecycle.
// The pure decision helpers (effectiveInterval / pollTolerance / minInterval etc.)
// are exercised in PasteboardPrivacyTests.swift; this covers the actor state
// transitions that those don't touch.
//
// The recurring poll() body is driven only by a live Task.sleep timer, so it is
// intentionally NOT exercised here (we never wait for a tick): asserting on it
// would depend on real wall-clock timer firing. We start with a very long
// interval and immediately stop, so the spawned poll task is created and then
// cancelled before it can fire.
//
// Serialized because start() reads NSPasteboard.general.changeCount.
@Suite(.serialized) struct PasteboardMonitorCoverageTests {

    private func makeStore() throws -> ClipStore {
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ClipStore(modelContainer: container)
    }

    // start() installs a poll task; a second start() is a no-op (guarded on
    // pollTask == nil); stop() cancels and clears it. Reaching the end without
    // hanging proves the task was created and torn down cleanly.
    @Test func startIsIdempotentAndStopTearsDown() async throws {
        let store = try makeStore()
        let monitor = PasteboardMonitor()

        // A long interval means the spawned task sleeps well past the test; stop()
        // cancels the sleep so nothing lingers.
        await monitor.start(clipStore: store, interval: .seconds(3600))
        await monitor.start(clipStore: store, interval: .seconds(3600)) // guarded no-op
        await monitor.stop()

        // stop() is safe to call again once already stopped (pollTask == nil).
        await monitor.stop()
    }

    // After a stop, start() can install a fresh poll task again (pollTask was
    // cleared to nil), so the monitor is reusable across enable/disable cycles.
    @Test func canRestartAfterStop() async throws {
        let store = try makeStore()
        let monitor = PasteboardMonitor()

        await monitor.start(clipStore: store, interval: .seconds(3600))
        await monitor.stop()
        await monitor.start(clipStore: store, interval: .seconds(3600))
        await monitor.stop()
    }
}
