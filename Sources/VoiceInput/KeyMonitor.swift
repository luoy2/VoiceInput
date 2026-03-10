import AppKit
import Foundation

class KeyMonitor {
    private var holdModifier: ModifierKeySpec
    private var toggleModifier: ModifierKeySpec
    private var sendModifier: ModifierKeySpec

    private var onHoldStart: () -> Void
    private var onHoldEnd: () -> Void
    private var onToggle: () -> Void
    private var onSend: () -> Void

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    // Hold tracking
    private var holdModifierDown = false

    // Toggle tracking (tap < 350ms, debounce 400ms)
    private var toggleModifierDown = false
    private var toggleDownTime: CFAbsoluteTime = 0
    private var lastToggleTime: CFAbsoluteTime = 0

    // Send tracking (tap < 350ms)
    private var sendModifierDown = false
    private var sendDownTime: CFAbsoluteTime = 0

    // If any regular key/mouse was pressed while a modifier is held, it's a combo, not a solo tap
    private var modifierInterrupted = false

    private var lastEventTime: TimeInterval = 0

    init(holdModifier: ModifierKeySpec, toggleModifier: ModifierKeySpec, sendModifier: ModifierKeySpec,
         onHoldStart: @escaping () -> Void, onHoldEnd: @escaping () -> Void,
         onToggle: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.holdModifier = holdModifier
        self.toggleModifier = toggleModifier
        self.sendModifier = sendModifier
        self.onHoldStart = onHoldStart
        self.onHoldEnd = onHoldEnd
        self.onToggle = onToggle
        self.onSend = onSend
    }

    func updateModifiers(hold: ModifierKeySpec, toggle: ModifierKeySpec, send: ModifierKeySpec) {
        holdModifier = hold
        toggleModifier = toggle
        sendModifier = send
        holdModifierDown = false
        toggleModifierDown = false
        sendModifierDown = false
        modifierInterrupted = false
    }

    func start() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }

        // Monitor regular key presses and mouse clicks to detect combos (Ctrl+C, Ctrl+click, etc.)
        let interruptMask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: interruptMask) { [weak self] _ in
            self?.markInterrupted()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: interruptMask) { [weak self] event in
            self?.markInterrupted()
            return event
        }
    }

    private func markInterrupted() {
        if toggleModifierDown || sendModifierDown {
            modifierInterrupted = true
        }
    }

    private func modifierIsActive(_ modifier: ModifierKeySpec, in flags: NSEvent.ModifierFlags) -> Bool {
        switch modifier.rawValue {
        case ModifierKeySpec.control.rawValue: return flags.contains(.control)
        case ModifierKeySpec.option.rawValue: return flags.contains(.option)
        case ModifierKeySpec.shift.rawValue: return flags.contains(.shift)
        case ModifierKeySpec.command.rawValue: return flags.contains(.command)
        case ModifierKeySpec.function.rawValue: return flags.contains(.function)
        default: return false
        }
    }

    private func handleFlags(_ event: NSEvent) {
        // Deduplicate events with same timestamp
        if event.timestamp == lastEventTime { return }
        lastEventTime = event.timestamp

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Process hold modifier (rawValue != 0 means not .none)
        if holdModifier.rawValue != 0 {
            let hasHold = modifierIsActive(holdModifier, in: flags)
            if hasHold && !holdModifierDown {
                holdModifierDown = true
                onHoldStart()
            } else if !hasHold && holdModifierDown {
                holdModifierDown = false
                onHoldEnd()
            }
        }

        // Process toggle modifier (skip if same as hold)
        if toggleModifier.rawValue != 0 && toggleModifier != holdModifier {
            let hasToggle = modifierIsActive(toggleModifier, in: flags)
            if hasToggle && !toggleModifierDown {
                toggleModifierDown = true
                toggleDownTime = CFAbsoluteTimeGetCurrent()
                if !sendModifierDown { modifierInterrupted = false }
            } else if !hasToggle && toggleModifierDown {
                toggleModifierDown = false
                let holdDuration = CFAbsoluteTimeGetCurrent() - toggleDownTime
                let now = CFAbsoluteTimeGetCurrent()
                if holdDuration < 0.35 && now - lastToggleTime > 0.4 && !modifierInterrupted {
                    lastToggleTime = now
                    onToggle()
                }
                if !sendModifierDown { modifierInterrupted = false }
            }
        }

        // Process send modifier (skip if same as hold or toggle)
        if sendModifier.rawValue != 0 && sendModifier != holdModifier && sendModifier != toggleModifier {
            let hasSend = modifierIsActive(sendModifier, in: flags)
            if hasSend && !sendModifierDown {
                sendModifierDown = true
                sendDownTime = CFAbsoluteTimeGetCurrent()
                if !toggleModifierDown { modifierInterrupted = false }
            } else if !hasSend && sendModifierDown {
                sendModifierDown = false
                let holdDuration = CFAbsoluteTimeGetCurrent() - sendDownTime
                if holdDuration < 0.35 && !modifierInterrupted {
                    onSend()
                }
                if !toggleModifierDown { modifierInterrupted = false }
            }
        }
    }

    deinit {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }
}
