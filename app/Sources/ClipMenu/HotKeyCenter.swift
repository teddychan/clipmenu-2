import AppKit
import Carbon.HIToolbox

// Swift wrapper around Carbon `RegisterEventHotKey` for system-wide hot-keys.
// Replaces the bundled PTHotKeys library (ARCHITECTURE.md §1 row 1; legacy
// AppController.m:601-633, CMUtilities.m:174-205). There is no first-party
// Swift API for global hot-keys, so Carbon remains the right tool.
//
// Scaffold status: fully compiles and can register/unregister combos, but it
// is NOT yet wired to the three ClipMenu menus — that happens with the
// hot-keys feature. Combos use Carbon key codes + Carbon modifier masks so the
// persisted representation matches the legacy `hotKeys` plist schema.

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// A key combination expressed with Carbon key code + modifier mask
    /// (e.g. `cmdKey | shiftKey`), matching the legacy stored format.
    struct Combo: Sendable, Hashable {
        var keyCode: UInt32
        var modifiers: UInt32
        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = 0x434C_4950 // 'CLIP'

    private init() {}

    /// Register a global hot-key. Returns an opaque id for later unregistering,
    /// or nil when RegisterEventHotKey refused the combo — callers must not
    /// treat a failed registration as live.
    func register(_ combo: Combo, action: @escaping () -> Void) -> UInt32? {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        handlers[id] = action

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            handlers[id] = nil
            return nil
        }
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
        handlers[id] = nil
    }

    func unregisterAll() {
        for ref in refs.values {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon hot-key events are delivered on the main run loop, so it is
        // safe to assume main-actor isolation inside the C callback.
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if err == noErr {
                let id = hotKeyID.id
                MainActor.assumeIsolated {
                    HotKeyCenter.shared.handle(id: id)
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            nil,
            &eventHandler
        )
    }
}
