import Cocoa

typealias HotkeyStyle = ProcessingMode.HotkeyStyle

struct ModeBinding {
    let modeId: UUID
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags  // .maskCommand etc. Use [] for no modifiers
    let style: HotkeyStyle
    let onStart: () -> Void
    let onStop: () -> Void
}

final class HotkeyManager {

    // MARK: - Configuration

    private var bindings: [ModeBinding] = []
    private var holdState: [UUID: Bool] = [:]
    private var toggleState: [UUID: Bool] = [:]
    private var wasModifierDown: [UUID: Bool] = [:]
    private var holdSafetyTimers: [UUID: Timer] = [:]
    /// Which toggle mode is currently active (recording). Only one can be active at a time.
    private var activeToggleModeId: UUID?

    /// Maximum hold duration before auto-stop (seconds).
    private let maxHoldDuration: TimeInterval = 120

    // MARK: - State

    /// When true, all hotkey events pass through unhandled (used during hotkey recording).
    var isSuppressed = false

    /// Called when recording is stopped by a different mode's hotkey.
    /// The UUID is the new mode's ID that should be used for processing.
    var onCrossModeStop: ((UUID) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Registration

    func registerBindings(_ newBindings: [ModeBinding]) {
        bindings = newBindings
        holdState = [:]
        toggleState = [:]
        wasModifierDown = [:]
        holdSafetyTimers.values.forEach { $0.invalidate() }
        holdSafetyTimers = [:]
    }

    // MARK: - Start / Stop

    @discardableResult
    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        holdState = [:]
        toggleState = [:]
        wasModifierDown = [:]
        holdSafetyTimers.values.forEach { $0.invalidate() }
        holdSafetyTimers = [:]
    }

    // MARK: - Event handling

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it, and recover any stuck hold states.
        // When macOS disables the tap (main thread blocked >1s), keyUp events are lost.
        // We must check if held keys are still physically down; if not, fire onStop.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            recoverStuckHolds()
            return Unmanaged.passUnretained(event)
        }

        // Pass all events through when suppressed (hotkey recording in progress)
        if isSuppressed {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        for binding in bindings {
            guard binding.keyCode == keyCode else { continue }

            if isModifierKeyCode(keyCode) {
                // Modifier keys: handle via flagsChanged only, don't swallow
                if type == .flagsChanged {
                    let pressed = isModifierPressed(keyCode: keyCode, flags: event.flags)
                    handleBindingEvent(binding: binding, pressed: pressed)
                }
                break
            } else {
                // Regular keys: check modifier flags match
                let requiredMods = binding.modifiers
                let currentMods = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
                guard currentMods == requiredMods else { continue }

                switch binding.style {
                case .hold:
                    if type == .keyDown {
                        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
                        if isRepeat != 0 { return nil }
                        handleBindingEvent(binding: binding, pressed: true)
                    } else if type == .keyUp {
                        handleBindingEvent(binding: binding, pressed: false)
                    }
                case .toggle:
                    if type == .keyDown {
                        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
                        if isRepeat != 0 { return nil }
                        let id = binding.modeId
                        if let activeId = activeToggleModeId, activeId != id {
                            // Cross-mode stop: different mode's key pressed while recording
                            toggleState[activeId] = false
                            activeToggleModeId = nil
                            onCrossModeStop?(id)
                        } else {
                            let isOn = toggleState[id] ?? false
                            toggleState[id] = !isOn
                            if !isOn {
                                activeToggleModeId = id
                                binding.onStart()
                            } else {
                                activeToggleModeId = nil
                                binding.onStop()
                            }
                        }
                    }
                }
                return nil  // Swallow matched regular key events
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Binding dispatch

    private func handleBindingEvent(binding: ModeBinding, pressed: Bool) {
        let id = binding.modeId

        switch binding.style {
        case .hold:
            let wasHolding = holdState[id] ?? false
            if pressed && !wasHolding {
                holdState[id] = true
                startSafetyTimer(for: binding)
                binding.onStart()
            } else if !pressed && wasHolding {
                holdState[id] = false
                cancelSafetyTimer(for: id)
                binding.onStop()
            }

        case .toggle:
            let wasDown = wasModifierDown[id] ?? false
            if pressed && !wasDown {
                wasModifierDown[id] = true
                if let activeId = activeToggleModeId, activeId != id {
                    // Cross-mode stop via modifier key
                    toggleState[activeId] = false
                    activeToggleModeId = nil
                    onCrossModeStop?(id)
                } else {
                    let isOn = toggleState[id] ?? false
                    toggleState[id] = !isOn
                    if !isOn {
                        activeToggleModeId = id
                        binding.onStart()
                    } else {
                        activeToggleModeId = nil
                        binding.onStop()
                    }
                }
            } else if !pressed {
                wasModifierDown[id] = false
            }
        }
    }

    // MARK: - Safety Timer

    private func startSafetyTimer(for binding: ModeBinding) {
        cancelSafetyTimer(for: binding.modeId)
        let id = binding.modeId
        holdSafetyTimers[id] = Timer.scheduledTimer(withTimeInterval: maxHoldDuration, repeats: false) { [weak self] _ in
            guard let self, self.holdState[id] == true else { return }
            NSLog("[HotkeyManager] Safety timer fired for mode %@, auto-stopping", id.uuidString)
            self.holdState[id] = false
            binding.onStop()
        }
    }

    private func cancelSafetyTimer(for id: UUID) {
        holdSafetyTimers[id]?.invalidate()
        holdSafetyTimers[id] = nil
    }

    // MARK: - Stuck Hold Recovery

    /// After a tap re-enable, check if any held keys were released while the tap was disabled.
    private func recoverStuckHolds() {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)

        for binding in bindings where binding.style == .hold {
            let id = binding.modeId
            guard holdState[id] == true else { continue }

            let stillDown: Bool
            if isModifierKeyCode(binding.keyCode) {
                stillDown = isModifierPressed(keyCode: binding.keyCode, flags: currentFlags)
            } else {
                stillDown = CGEventSource.keyState(.combinedSessionState, key: binding.keyCode)
            }

            if !stillDown {
                NSLog("[HotkeyManager] Recovering stuck hold for mode %@", id.uuidString)
                holdState[id] = false
                cancelSafetyTimer(for: id)
                binding.onStop()
            }
        }
    }

    // MARK: - Helpers

    private func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool {
        [54, 55, 56, 58, 59, 60, 61, 62].contains(keyCode)
    }

    private func isModifierPressed(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        default: return false
        }
    }
}

// MARK: - C callback

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type: type, event: event)
}
