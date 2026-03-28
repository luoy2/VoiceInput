import Foundation
import IOKit
import IOKit.hid

/// Button identifiers for gamepad mapping
enum GamepadButton: Int, CaseIterable, Codable {
    case none = -1
    case a = 0
    case b = 1
    case x = 2
    case y = 3
    case leftShoulder = 4
    case rightShoulder = 5

    var displayName: String {
        switch self {
        case .none: return L("无", "None")
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

    // MARK: - UserDefaults persistence

    private static let holdButtonKey = "tf_gamepadHoldButton"
    private static let toggleButtonKey = "tf_gamepadToggleButton"
    private static let sendButtonKey = "tf_gamepadSendButton"

    static var savedHoldButton: GamepadButton {
        get {
            guard let raw = UserDefaults.standard.object(forKey: holdButtonKey) as? Int else { return .a }
            return GamepadButton(rawValue: raw) ?? .a
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: holdButtonKey) }
    }

    static var savedToggleButton: GamepadButton {
        get {
            guard let raw = UserDefaults.standard.object(forKey: toggleButtonKey) as? Int else { return .none }
            return GamepadButton(rawValue: raw) ?? .none
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: toggleButtonKey) }
    }

    static var savedSendButton: GamepadButton {
        get {
            guard let raw = UserDefaults.standard.object(forKey: sendButtonKey) as? Int else { return .b }
            return GamepadButton(rawValue: raw) ?? .b
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sendButtonKey) }
    }
}

/// Monitors a connected game controller globally via IOKit HID.
/// Works regardless of app focus (unlike GCController).
/// Supports both standard HID button page (8BitDo) and raw report parsing (Pro Controller).
class GamepadMonitor {
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onToggleTap: (() -> Void)?
    var onSendTap: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onButtonCaptured: ((GamepadButton) -> Void)?

    private(set) var isConnected = false
    private var holdButton: GamepadButton
    private var toggleButton: GamepadButton
    private var sendButton: GamepadButton
    private var holdButtonDown = false
    private var toggleButtonDown = false
    private var sendButtonDown = false
    private var captureMode = false

    private var hidManager: IOHIDManager?
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private var lastRawButtons: [GamepadButton: Bool] = [:]
    private var usesStandardButtons = false

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
            NSLog("[GamepadMonitor] HID Gamepad connected: %@", name)
            DebugFileLogger.log("GamepadMonitor: connected \(name)")
            monitor.isConnected = true
            monitor.registerRawReportCallback(for: device)
            DispatchQueue.main.async { monitor.onConnectionChanged?(true) }
        }, refSelf)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<GamepadMonitor>.fromOpaque(context).takeUnretainedValue()
            NSLog("[GamepadMonitor] HID Gamepad disconnected")
            DebugFileLogger.log("GamepadMonitor: disconnected")
            monitor.isConnected = false
            monitor.holdButtonDown = false
            monitor.toggleButtonDown = false
            monitor.sendButtonDown = false
            monitor.lastRawButtons.removeAll()
            DispatchQueue.main.async { monitor.onConnectionChanged?(false) }
        }, refSelf)

        // Input value callback for standard HID button page (e.g. 8BitDo)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<GamepadMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleHIDValue(value)
        }, refSelf)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        NSLog("[GamepadMonitor] HID GamepadMonitor started")
        DebugFileLogger.log("GamepadMonitor: started")
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

    // MARK: - Raw Report Callback (for Pro Controller etc.)

    private func registerRawReportCallback(for device: IOHIDDevice) {
        let bufferSize = 512
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        reportBufferPtr = buffer

        let refSelf = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, reportID, report, reportLength in
            guard let context else { return }
            let monitor = Unmanaged<GamepadMonitor>.fromOpaque(context).takeUnretainedValue()
            // Skip if this controller uses standard button page
            guard !monitor.usesStandardButtons else { return }
            monitor.handleRawReport(reportID: reportID, report: report, length: Int(reportLength))
        }, refSelf)
    }

    /// Parse raw input report for Nintendo Pro Controller (report ID 0x30)
    /// Report layout (after report ID byte):
    ///   [0] timer  [1] battery  [2] buttons1  [3] buttons2  [4] buttons3  [5-10] sticks  [11+] IMU
    /// buttons1: Y=0x01 X=0x02 B=0x04 A=0x08 SR_R=0x10 SL_R=0x20 R=0x40 ZR=0x80
    /// buttons2: Minus=0x01 Plus=0x02 RStick=0x04 LStick=0x08 Home=0x10 Capture=0x20
    /// buttons3: Down=0x01 Up=0x02 Right=0x04 Left=0x08 SR_L=0x10 SL_L=0x20 L=0x40 ZL=0x80
    private func handleRawReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard reportID == 0x30, length >= 5 else { return }

        let btn1 = report[2]
        let btn3 = report[4]

        let buttonStates: [(GamepadButton, Bool)] = [
            (.a, btn1 & 0x08 != 0),
            (.b, btn1 & 0x04 != 0),
            (.x, btn1 & 0x02 != 0),
            (.y, btn1 & 0x01 != 0),
            (.leftShoulder, btn3 & 0x40 != 0),
            (.rightShoulder, btn1 & 0x40 != 0),
        ]

        for (button, pressed) in buttonStates {
            let wasPressed = lastRawButtons[button] ?? false
            if pressed != wasPressed {
                lastRawButtons[button] = pressed
                handleButtonStateChange(button: button, pressed: pressed)
            }
        }
    }

    // MARK: - Standard HID Button Page Handling (8BitDo etc.)

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        // Only care about Button page (0x09)
        guard usagePage == Int(kHIDPage_Button) else { return }

        // Mark that this controller uses standard buttons, skip raw report parsing
        usesStandardButtons = true

        let pressed = intValue != 0
        guard let button = GamepadButton.fromHIDUsage(usage) else {
            // Capture mode: accept any button press even if not in our mapping
            if captureMode && pressed {
                NSLog("[GamepadMonitor] HID capture: unknown usage=%d pressed", usage)
            }
            return
        }

        handleButtonStateChange(button: button, pressed: pressed)
    }

    // MARK: - Shared Button Logic

    private func handleButtonStateChange(button: GamepadButton, pressed: Bool) {
        // Capture mode: any button press captures it
        if captureMode && pressed {
            NSLog("[GamepadMonitor] Captured: %@", button.displayName)
            DebugFileLogger.log("GamepadMonitor: captured \(button.displayName)")
            DispatchQueue.main.async { [self] in
                onButtonCaptured?(button)
                captureMode = false
            }
            return
        }

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
        reportBufferPtr?.deallocate()
    }
}
