// HotkeyManager: system-wide keyboard shortcuts via Carbon HIToolbox.
//
// Why Carbon? It's the only public macOS API that fires hotkeys regardless of which
// app has focus — NSEvent local monitors only work while your app is key, and global
// NSEvent monitors require Accessibility permission. Carbon's RegisterEventHotKey
// works for accessory apps without extra entitlements.
//
// C callback pattern:
//   InstallEventHandler takes a plain C function pointer, which can't capture Swift
//   context. We pass `self` as a void* (via Unmanaged.passUnretained) and cast it
//   back inside the callback with Unmanaged.fromOpaque. "passUnretained" means ARC
//   does NOT bump the retain count — safe here because HotkeyManager's lifetime is
//   tied to AppController which owns the app's entire run.
//
//   The callback fires on the main run-loop thread, but to stay safe with Swift's
//   strict concurrency we hop to @MainActor via Task before touching any Swift state.

import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    enum Action { case playPause, next, prev, restart, toggleHide, toggleMove, toggleCaptureExclusion, quit }

    private var handler: (Action) -> Void
    private var refs: [EventHotKeyRef] = []         // keep refs alive; needed for unregister
    private var idToAction: [UInt32: Action] = [:]  // maps hotkey ID → Action
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init(handler: @escaping (Action) -> Void) {
        self.handler = handler
        installEventHandler()
        registerAll()
    }

    /// Register a single Carbon event handler that intercepts all kEventHotKeyPressed
    /// events for this application target.
    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // passUnretained: we don't want an extra retain; AppController keeps us alive.
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                // Extract the EventHotKeyID that was embedded when we registered the key.
                var hkID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                // Cast void* back to HotkeyManager without releasing.
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hkID.id
                // Hop to @MainActor so we can safely access mgr's properties.
                Task { @MainActor in
                    if let action = mgr.idToAction[id] {
                        mgr.handler(action)
                    }
                }
                return noErr
            },
            1,
            &spec,
            me,
            &eventHandler
        )
    }

    private func registerAll() {
        let mods = UInt32(controlKey | optionKey)  // ⌃⌥
        let bindings: [(UInt32, Action)] = [
            (UInt32(kVK_Space),      .playPause),
            (UInt32(kVK_RightArrow), .next),
            (UInt32(kVK_LeftArrow),  .prev),
            (UInt32(kVK_ANSI_R),     .restart),
            (UInt32(kVK_ANSI_H),     .toggleHide),
            (UInt32(kVK_ANSI_M),     .toggleMove),
            (UInt32(kVK_ANSI_C),     .toggleCaptureExclusion),
            (UInt32(kVK_ANSI_Q),     .quit),
        ]
        for (keyCode, action) in bindings {
            register(keyCode: keyCode, modifiers: mods, action: action)
        }
    }

    /// Register one hotkey and store its ref so it can be unregistered on deinit.
    private func register(keyCode: UInt32, modifiers: UInt32, action: Action) {
        let id = nextID
        nextID += 1
        idToAction[id] = action
        // The signature is a four-byte creator code ('VSTN') that namespaces our IDs
        // to avoid collisions with hotkeys registered by other frameworks.
        let hkID = EventHotKeyID(signature: OSType(0x5653544E) /* 'VSTN' */, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
        else { fputs("warn: hotkey \(action) failed: \(status)\n", stderr) }
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let eh = eventHandler { RemoveEventHandler(eh) }
    }
}
