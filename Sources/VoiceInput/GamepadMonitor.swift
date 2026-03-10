import Foundation
import IOKit
import IOKit.hid

/// Button identifiers for gamepad mapping
enum GamepadButton: Int, CaseIterable {
    case none = -1
    case a = 0
    case b = 1
    case x = 2
    case y = 3
    case leftShoulder = 4
    case rightShoulder = 5

    var displayName: String {
        switch self {
        case .none: return "无"
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .leftShoulder: return "L"
        case .rightShoulder: return "R"
        }
    }

    /// HID usage ID for the button (Button usage page 0x09)
    /// 8BitDo Zero 2 actual mapping
    var hidUsageID: Int {
        switch self {
        case .none: return -1
        case .a: return 2
        case .b: return 1
        case .x: return 4
        case .y: return 3
        case .leftShoulder: return 5
        case .rightShoulder: return 6
        }
    }

    static func fromHIDUsage(_ usage: Int) -> GamepadButton? {
        allCases.first { $0 != .none && $0.hidUsageID == usage }
    }
}

/// Monitors a connected game controller globally via IOKit HID.
/// Works regardless of app focus (unlike GCController).
class GamepadMonitor {
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onToggleTap: (() -> Void)?
    var onSendTap: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onButtonCaptured: ((GamepadButton) -> Void)?

    private(set) var isConnected = false
    private var holdButton: GamepadButton = .a
    private var toggleButton: GamepadButton = .none
    private var sendButton: GamepadButton = .b
    private var holdButtonDown = false
    private var toggleButtonDown = false
    private var sendButtonDown = false
    private var captureMode = false

    private var hidManager: IOHIDManager?

    init(holdButton: GamepadButton = .a, toggleButton: GamepadButton = .none, sendButton: GamepadButton = .b) {
        self.holdButton = holdButton
        self.toggleButton = toggleButton
        self.sendButton = sendButton
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        // Match game controllers (GD_GamePad, GD_Joystick, GD_MultiAxisController)
        let matchingCriteria: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

        // Device connect/disconnect callbacks
        let refSelf = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<GamepadMonitor>.fromOpaque(context).takeUnretainedValue()
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
            try? "HID Gamepad connected: \(name)\n".appendToFile("/tmp/voiceinput-debug.log")
            monitor.isConnected = true
            DispatchQueue.main.async { monitor.onConnectionChanged?(true) }
        }, refSelf)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<GamepadMonitor>.fromOpaque(context).takeUnretainedValue()
            try? "HID Gamepad disconnected\n".appendToFile("/tmp/voiceinput-debug.log")
            monitor.isConnected = false
            monitor.holdButtonDown = false
            monitor.toggleButtonDown = false
            monitor.sendButtonDown = false
            DispatchQueue.main.async { monitor.onConnectionChanged?(false) }
        }, refSelf)

        // Input value callback for button events
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<GamepadMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleHIDValue(value)
        }, refSelf)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        try? "HID GamepadMonitor started\n".appendToFile("/tmp/voiceinput-debug.log")
    }

    func updateHoldButton(_ button: GamepadButton) {
        holdButton = button
        holdButtonDown = false
    }

    func updateToggleButton(_ button: GamepadButton) {
        toggleButton = button
        toggleButtonDown = false
    }

    func updateSendButton(_ button: GamepadButton) {
        sendButton = button
        sendButtonDown = false
    }

    // MARK: - Capture Mode

    func startCapture() {
        captureMode = true
    }

    func stopCapture() {
        captureMode = false
        onButtonCaptured = nil
    }

    // MARK: - HID Input Handling

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        // Only care about Button page (0x09)
        guard usagePage == Int(kHIDPage_Button) else { return }

        let pressed = intValue != 0

        // Capture mode: any button press captures it
        if captureMode && pressed {
            if let button = GamepadButton.fromHIDUsage(usage) {
                try? "HID capture: usage=\(usage) → \(button.displayName)\n".appendToFile("/tmp/voiceinput-debug.log")
                DispatchQueue.main.async { [self] in
                    onButtonCaptured?(button)
                    captureMode = false
                }
            } else {
                try? "HID capture: unknown usage=\(usage) pressed\n".appendToFile("/tmp/voiceinput-debug.log")
            }
            return
        }

        // Normal mode: check if this is one of our buttons
        guard let button = GamepadButton.fromHIDUsage(usage) else { return }

        if button == holdButton && holdButton != .none {
            DispatchQueue.main.async { [self] in
                if pressed && !holdButtonDown {
                    holdButtonDown = true
                    onHoldStart?()
                } else if !pressed && holdButtonDown {
                    holdButtonDown = false
                    onHoldEnd?()
                }
            }
        } else if button == toggleButton && toggleButton != .none {
            DispatchQueue.main.async { [self] in
                if pressed {
                    toggleButtonDown = true
                } else if toggleButtonDown {
                    toggleButtonDown = false
                    onToggleTap?()
                }
            }
        } else if button == sendButton && sendButton != .none {
            DispatchQueue.main.async { [self] in
                if pressed {
                    sendButtonDown = true
                } else if sendButtonDown {
                    sendButtonDown = false
                    onSendTap?()
                }
            }
        }
    }

    deinit {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
