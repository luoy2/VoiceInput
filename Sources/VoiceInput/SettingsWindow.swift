import AppKit
import CoreGraphics

// MARK: - ModifierKeySpec

struct ModifierKeySpec: Equatable {
    let rawValue: UInt64
    let displayName: String

    var cgFlags: CGEventFlags {
        CGEventFlags(rawValue: rawValue)
    }

    static let none = ModifierKeySpec(rawValue: 0, displayName: "无")
    static let control = ModifierKeySpec(rawValue: CGEventFlags.maskControl.rawValue, displayName: "Left Ctrl")
    static let option = ModifierKeySpec(rawValue: CGEventFlags.maskAlternate.rawValue, displayName: "Option")
    static let shift = ModifierKeySpec(rawValue: CGEventFlags.maskShift.rawValue, displayName: "Shift")
    static let command = ModifierKeySpec(rawValue: CGEventFlags.maskCommand.rawValue, displayName: "Command")
    static let function = ModifierKeySpec(rawValue: CGEventFlags.maskSecondaryFn.rawValue, displayName: "Fn")

    static let all: [ModifierKeySpec] = [.control, .option, .shift, .command, .function]

    static func fromEvent(_ event: NSEvent) -> ModifierKeySpec? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let mapping: [(NSEvent.ModifierFlags, ModifierKeySpec)] = [
            (.control, .control), (.option, .option), (.shift, .shift),
            (.command, .command), (.function, .function)
        ]
        for (flag, spec) in mapping where flags.contains(flag) {
            return spec
        }
        return nil
    }
}

// MARK: - ASR Provider

enum ASRProvider: Int {
    case local = 0
    case groq = 1
    case gemini = 2
    case funasrStreaming = 3

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .groq: return "Groq"
        case .gemini: return "Gemini"
        case .funasrStreaming: return "FunASR"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .local: return "http://localhost:10301/v1/audio/transcriptions"
        case .groq: return "https://api.groq.com/openai/v1/audio/transcriptions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .funasrStreaming: return "ws://localhost:10096"
        }
    }

    var defaultModel: String {
        switch self {
        case .local: return "sensevoice"
        case .groq: return "whisper-large-v3-turbo"
        case .gemini: return "gemini-3.1-flash-lite-preview"
        case .funasrStreaming: return "2pass"
        }
    }

    var needsApiKey: Bool {
        switch self {
        case .local, .funasrStreaming: return false
        case .groq, .gemini: return true
        }
    }

    var isStreaming: Bool {
        switch self {
        case .funasrStreaming: return true
        case .local, .groq, .gemini: return false
        }
    }

    var helpText: String {
        switch self {
        case .local:
            return "需要本地部署 OpenAI 兼容的 ASR 服务（如 SenseVoice、Whisper）。\nEndpoint 需实现 POST /v1/audio/transcriptions，接受 multipart/form-data（file + model 字段），返回 JSON {\"text\": \"...\"}。"
        case .groq:
            return "使用 Groq 云端 Whisper 模型，速度极快且有免费额度。\n支持模型：whisper-large-v3-turbo、whisper-large-v3、distil-whisper-large-v3-en。"
        case .gemini:
            return "使用 Google Gemini 多模态模型进行语音转文字。\n通过 generateContent API 发送 base64 音频，适合中英文混合场景。"
        case .funasrStreaming:
            return "使用 FunASR WebSocket 流式识别，实时显示部分结果。\nEndpoint 格式为 ws://host:port，Model 填写模式（2pass/online/offline）。"
        }
    }

    var helpLinkTitle: String? {
        switch self {
        case .local, .funasrStreaming: return nil
        case .groq: return "前往 Groq Console 申请 API Key →"
        case .gemini: return "前往 Google AI Studio 申请 API Key →"
        }
    }

    var helpLinkURL: String? {
        switch self {
        case .local, .funasrStreaming: return nil
        case .groq: return "https://console.groq.com/keys"
        case .gemini: return "https://aistudio.google.com/apikey"
        }
    }
}

// MARK: - AppSettings

struct AppSettings {
    // Keyboard: 3 actions
    var holdModifierRawValue: UInt64
    var holdModifierName: String
    var toggleModifierRawValue: UInt64
    var toggleModifierName: String
    var sendModifierRawValue: UInt64
    var sendModifierName: String

    // ASR
    var asrProvider: ASRProvider
    var asrEndpoint: String
    var asrModel: String
    var asrApiKey: String
    var groqApiKey: String
    var geminiApiKey: String
    var inputDeviceID: UInt32  // AudioDeviceID, 0 = system default

    // Gamepad: 3 actions
    var gamepadEnabled: Bool
    var gamepadHoldButton: GamepadButton
    var gamepadToggleButton: GamepadButton
    var gamepadSendButton: GamepadButton

    var holdModifier: ModifierKeySpec {
        ModifierKeySpec(rawValue: holdModifierRawValue, displayName: holdModifierName)
    }

    var toggleModifier: ModifierKeySpec {
        ModifierKeySpec(rawValue: toggleModifierRawValue, displayName: toggleModifierName)
    }

    var sendModifier: ModifierKeySpec {
        ModifierKeySpec(rawValue: sendModifierRawValue, displayName: sendModifierName)
    }

    /// Returns the API key for the current provider
    var activeApiKey: String {
        switch asrProvider {
        case .local, .funasrStreaming: return ""
        case .groq: return groqApiKey
        case .gemini: return geminiApiKey
        }
    }

    static func load() -> AppSettings {
        let ud = UserDefaults.standard

        // Migration: read old keys if new ones don't exist
        let hasNewKeys = ud.object(forKey: "holdModifierRawValue") != nil ||
                         ud.object(forKey: "toggleModifierRawValue") != nil

        let holdRaw: UInt64
        let holdName: String
        let toggleRaw: UInt64
        let toggleName: String
        let sendRaw: UInt64
        let sendName: String

        if hasNewKeys {
            holdRaw = ud.object(forKey: "holdModifierRawValue") as? UInt64 ?? 0
            holdName = ud.string(forKey: "holdModifierName") ?? ModifierKeySpec.none.displayName
            toggleRaw = ud.object(forKey: "toggleModifierRawValue") as? UInt64 ?? ModifierKeySpec.control.rawValue
            toggleName = ud.string(forKey: "toggleModifierName") ?? ModifierKeySpec.control.displayName
            sendRaw = ud.object(forKey: "sendModifierRawValue") as? UInt64 ?? 0
            sendName = ud.string(forKey: "sendModifierName") ?? ModifierKeySpec.none.displayName
        } else {
            // Migrate old single modifier to toggleModifier
            let oldRaw = ud.object(forKey: "modifierRawValue") as? UInt64 ?? ModifierKeySpec.control.rawValue
            let oldName = ud.string(forKey: "modifierName") ?? ModifierKeySpec.control.displayName
            holdRaw = 0
            holdName = ModifierKeySpec.none.displayName
            toggleRaw = oldRaw
            toggleName = oldName
            sendRaw = 0
            sendName = ModifierKeySpec.none.displayName
        }

        let provider = ASRProvider(rawValue: ud.integer(forKey: "asrProvider")) ?? .local
        let endpoint = ud.string(forKey: "asrEndpoint") ?? provider.defaultEndpoint
        let model = ud.string(forKey: "asrModel") ?? provider.defaultModel
        let groqKey = ud.string(forKey: "groqApiKey") ?? ""
        let geminiKey = ud.string(forKey: "geminiApiKey") ?? ""
        let deviceID = UInt32(ud.integer(forKey: "inputDeviceID"))
        let gamepadEnabled = ud.bool(forKey: "gamepadEnabled")

        // Gamepad migration: old "gamepadButton" -> gamepadHoldButton
        let hasNewGamepad = ud.object(forKey: "gamepadHoldButton") != nil
        let gamepadHoldButton: GamepadButton
        let gamepadToggleButton: GamepadButton
        let gamepadSendButton: GamepadButton

        if hasNewGamepad {
            gamepadHoldButton = GamepadButton(rawValue: ud.integer(forKey: "gamepadHoldButton")) ?? .a
            gamepadToggleButton = GamepadButton(rawValue: ud.integer(forKey: "gamepadToggleButton")) ?? .none
            gamepadSendButton = GamepadButton(rawValue: ud.integer(forKey: "gamepadSendButton")) ?? .b
        } else {
            // Migrate old keys
            gamepadHoldButton = GamepadButton(rawValue: ud.integer(forKey: "gamepadButton")) ?? .a
            gamepadToggleButton = .none
            gamepadSendButton = GamepadButton(rawValue: ud.integer(forKey: "gamepadSendButton")) ?? .b
        }

        // Migrate old single apiKey to groq if present
        let oldKey = ud.string(forKey: "asrApiKey") ?? ""
        let finalGroqKey = groqKey.isEmpty ? oldKey : groqKey

        return AppSettings(
            holdModifierRawValue: holdRaw, holdModifierName: holdName,
            toggleModifierRawValue: toggleRaw, toggleModifierName: toggleName,
            sendModifierRawValue: sendRaw, sendModifierName: sendName,
            asrProvider: provider, asrEndpoint: endpoint, asrModel: model,
            asrApiKey: "", groqApiKey: finalGroqKey, geminiApiKey: geminiKey,
            inputDeviceID: deviceID,
            gamepadEnabled: gamepadEnabled,
            gamepadHoldButton: gamepadHoldButton, gamepadToggleButton: gamepadToggleButton,
            gamepadSendButton: gamepadSendButton
        )
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(holdModifierRawValue, forKey: "holdModifierRawValue")
        ud.set(holdModifierName, forKey: "holdModifierName")
        ud.set(toggleModifierRawValue, forKey: "toggleModifierRawValue")
        ud.set(toggleModifierName, forKey: "toggleModifierName")
        ud.set(sendModifierRawValue, forKey: "sendModifierRawValue")
        ud.set(sendModifierName, forKey: "sendModifierName")
        ud.set(asrProvider.rawValue, forKey: "asrProvider")
        ud.set(asrEndpoint, forKey: "asrEndpoint")
        ud.set(asrModel, forKey: "asrModel")
        ud.set(groqApiKey, forKey: "groqApiKey")
        ud.set(geminiApiKey, forKey: "geminiApiKey")
        ud.set(Int(inputDeviceID), forKey: "inputDeviceID")
        ud.set(gamepadEnabled, forKey: "gamepadEnabled")
        ud.set(gamepadHoldButton.rawValue, forKey: "gamepadHoldButton")
        ud.set(gamepadToggleButton.rawValue, forKey: "gamepadToggleButton")
        ud.set(gamepadSendButton.rawValue, forKey: "gamepadSendButton")
    }
}

// MARK: - KeyPill (the rounded key label like "Left Ctrl")

private class KeyPill: NSView {
    private let label = NSTextField(labelWithString: "")
    var isCapturing = false {
        didSet { updateAppearance() }
    }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; invalidateIntrinsicContentSize() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 24),
            heightAnchor.constraint(equalToConstant: 32),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        if isCapturing {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            label.textColor = .controlAccentColor
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            label.textColor = .labelColor
        }
    }
}

// MARK: - PastableSecureTextField

private class PastableSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - SettingsWindowController

private enum CaptureTarget {
    case holdKey, toggleKey, sendKey
    case gamepadHold, gamepadToggle, gamepadSend
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    // Keyboard pills
    private let holdKeyPill = KeyPill()
    private let toggleKeyPill = KeyPill()
    private let sendKeyPill = KeyPill()

    // Gamepad pills
    private let gamepadHoldPill = KeyPill()
    private let gamepadTogglePill = KeyPill()
    private let gamepadSendPill = KeyPill()

    // Gamepad status labels
    private let gamepadHoldStatusLabel = NSTextField(labelWithString: "")
    private let gamepadToggleStatusLabel = NSTextField(labelWithString: "")
    private let gamepadSendStatusLabel = NSTextField(labelWithString: "")

    // Other UI elements
    private let inputDevicePopup = NSPopUpButton(title: "", target: nil, action: nil)
    private let providerSegment = NSSegmentedControl(labels: ["Local", "Groq", "Gemini", "FunASR"], trackingMode: .selectOne, target: nil, action: nil)
    private let endpointField = NSTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let apiKeyField = PastableSecureTextField(string: "")
    private let apiKeyRow = NSStackView()
    private let helpLabel = NSTextField(wrappingLabelWithString: "")
    private let testButton = NSButton(title: "Test", target: nil, action: nil)
    private let testStatusLabel = NSTextField(labelWithString: "")
    private let gamepadToggleSwitch = NSSwitch()
    private let gamepadStatusLabel = NSTextField(labelWithString: "")
    private var gamepadMonitor: GamepadMonitor?
    private var inputDevices: [AudioDevice] = []

    private var settings: AppSettings
    private var onChange: (AppSettings) -> Void
    private var captureMonitor: Any?
    private var activeCaptureTarget: CaptureTarget?

    init(settings: AppSettings, gamepadMonitor: GamepadMonitor?, onChange: @escaping (AppSettings) -> Void) {
        self.settings = settings
        self.gamepadMonitor = gamepadMonitor
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VoiceInputSettings")

        super.init(window: window)
        window.delegate = self
        buildUI()
        applySettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(settings: AppSettings) {
        self.settings = settings
        applySettings()
    }

    func updateGamepadMonitor(_ monitor: GamepadMonitor?) {
        self.gamepadMonitor = monitor
    }

    func windowWillClose(_ notification: Notification) {
        stopCapture()
        stopGamepadCapture()
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])

        // Section: 键盘快捷键
        stack.addArrangedSubview(sectionHeader(icon: "keyboard", title: "键盘快捷键"))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(separator())
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // Hold-to-talk row
        buildActionRow(
            title: "按住说话", description: "按住录音，松开转文字并发送",
            pill: holdKeyPill, action: #selector(startHoldKeyCapture), in: stack
        )
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Toggle row
        buildActionRow(
            title: "切换录音", description: "按下开始/停止语音输入",
            pill: toggleKeyPill, action: #selector(startToggleKeyCapture), in: stack
        )
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // Input device row
        let inputDeviceRow = NSStackView()
        inputDeviceRow.orientation = .horizontal
        inputDeviceRow.alignment = .centerY
        inputDeviceRow.spacing = 0

        let inputDeviceTextStack = NSStackView()
        inputDeviceTextStack.orientation = .vertical
        inputDeviceTextStack.alignment = .leading
        inputDeviceTextStack.spacing = 2

        let inputDeviceTitle = NSTextField(labelWithString: "输入设备")
        inputDeviceTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        inputDeviceTextStack.addArrangedSubview(inputDeviceTitle)

        let inputDeviceDesc = NSTextField(labelWithString: "选择麦克风输入源。")
        inputDeviceDesc.font = .systemFont(ofSize: 12)
        inputDeviceDesc.textColor = .secondaryLabelColor
        inputDeviceTextStack.addArrangedSubview(inputDeviceDesc)

        inputDeviceRow.addArrangedSubview(inputDeviceTextStack)

        let spacer2 = NSView()
        spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inputDeviceRow.addArrangedSubview(spacer2)

        inputDevicePopup.target = self
        inputDevicePopup.action = #selector(inputDeviceChanged)
        inputDevicePopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        inputDeviceRow.addArrangedSubview(inputDevicePopup)

        inputDeviceRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(inputDeviceRow)
        inputDeviceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.setCustomSpacing(24, after: inputDeviceRow)

        // Section: 手柄
        stack.addArrangedSubview(sectionHeader(icon: "gamecontroller", title: "手柄"))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(separator())
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // Gamepad enable row
        let gamepadRow = NSStackView()
        gamepadRow.orientation = .horizontal
        gamepadRow.alignment = .centerY
        gamepadRow.spacing = 0

        let gamepadTextStack = NSStackView()
        gamepadTextStack.orientation = .vertical
        gamepadTextStack.alignment = .leading
        gamepadTextStack.spacing = 2

        let gamepadTitle = NSTextField(labelWithString: "启用手柄")
        gamepadTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        gamepadTextStack.addArrangedSubview(gamepadTitle)

        let gamepadDesc = NSTextField(labelWithString: "连接手柄后配置按键。")
        gamepadDesc.font = .systemFont(ofSize: 12)
        gamepadDesc.textColor = .secondaryLabelColor
        gamepadTextStack.addArrangedSubview(gamepadDesc)

        gamepadRow.addArrangedSubview(gamepadTextStack)

        let spacerGP1 = NSView()
        spacerGP1.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gamepadRow.addArrangedSubview(spacerGP1)

        gamepadToggleSwitch.target = self
        gamepadToggleSwitch.action = #selector(gamepadToggleChanged)
        gamepadRow.addArrangedSubview(gamepadToggleSwitch)

        gamepadRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gamepadRow)
        gamepadRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(12, after: gamepadRow)

        // Gamepad hold button row
        buildGamepadActionRow(
            title: "按住说话", statusLabel: gamepadHoldStatusLabel,
            defaultStatus: "按住录音，松开转文字并发送",
            pill: gamepadHoldPill, action: #selector(startGamepadHoldCapture), in: stack
        )
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Gamepad toggle button row
        buildGamepadActionRow(
            title: "切换录音", statusLabel: gamepadToggleStatusLabel,
            defaultStatus: "按下开始/停止语音输入",
            pill: gamepadTogglePill, action: #selector(startGamepadToggleCapture), in: stack
        )
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Gamepad send button row
        buildGamepadActionRow(
            title: "发送", statusLabel: gamepadSendStatusLabel,
            defaultStatus: "按一下模拟回车",
            pill: gamepadSendPill, action: #selector(startGamepadSendCapture), in: stack
        )

        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)

        // Section: ASR 服务
        stack.addArrangedSubview(sectionHeader(icon: "network", title: "ASR 服务"))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(separator())
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // Provider row
        let providerRow = NSStackView()
        providerRow.orientation = .horizontal
        providerRow.alignment = .centerY
        providerRow.spacing = 8

        let providerLabel = NSTextField(labelWithString: "Provider")
        providerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        providerLabel.setContentHuggingPriority(.required, for: .horizontal)
        providerRow.addArrangedSubview(providerLabel)

        providerSegment.target = self
        providerSegment.action = #selector(providerChanged)
        providerSegment.segmentStyle = .rounded
        providerRow.addArrangedSubview(providerSegment)

        providerRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(providerRow)
        providerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.setCustomSpacing(10, after: providerRow)

        // Endpoint row
        let endpointRow = NSStackView()
        endpointRow.orientation = .horizontal
        endpointRow.alignment = .centerY
        endpointRow.spacing = 8

        let endpointLabel = NSTextField(labelWithString: "Endpoint")
        endpointLabel.font = .systemFont(ofSize: 13, weight: .medium)
        endpointLabel.setContentHuggingPriority(.required, for: .horizontal)
        endpointRow.addArrangedSubview(endpointLabel)

        endpointField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        endpointField.delegate = self
        endpointField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        endpointRow.addArrangedSubview(endpointField)

        endpointRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(endpointRow)
        endpointRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.setCustomSpacing(10, after: endpointRow)

        // Model row
        let modelRow = NSStackView()
        modelRow.orientation = .horizontal
        modelRow.alignment = .centerY
        modelRow.spacing = 8

        let modelLabel = NSTextField(labelWithString: "Model")
        modelLabel.font = .systemFont(ofSize: 13, weight: .medium)
        modelLabel.setContentHuggingPriority(.required, for: .horizontal)
        modelRow.addArrangedSubview(modelLabel)

        modelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        modelField.delegate = self
        modelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        modelRow.addArrangedSubview(modelField)

        modelRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(modelRow)
        modelRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.setCustomSpacing(10, after: modelRow)

        // API Key row
        apiKeyRow.orientation = .horizontal
        apiKeyRow.alignment = .centerY
        apiKeyRow.spacing = 8

        let apiKeyLabel = NSTextField(labelWithString: "API Key")
        apiKeyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        apiKeyLabel.setContentHuggingPriority(.required, for: .horizontal)
        apiKeyRow.addArrangedSubview(apiKeyLabel)

        apiKeyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        apiKeyField.placeholderString = "Groq API Key"
        apiKeyField.delegate = self
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        apiKeyRow.addArrangedSubview(apiKeyField)

        apiKeyRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(apiKeyRow)
        apiKeyRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.setCustomSpacing(6, after: apiKeyRow)

        // Help label
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .tertiaryLabelColor
        helpLabel.isSelectable = true
        helpLabel.allowsEditingTextAttributes = true
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(helpLabel)
        helpLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.setCustomSpacing(12, after: helpLabel)

        // Test row
        let testRow = NSStackView()
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 10

        testButton.target = self
        testButton.action = #selector(testConnection)
        testButton.bezelStyle = .rounded
        testRow.addArrangedSubview(testButton)

        testStatusLabel.font = .systemFont(ofSize: 12)
        testStatusLabel.textColor = .secondaryLabelColor
        testRow.addArrangedSubview(testStatusLabel)

        stack.addArrangedSubview(testRow)
    }

    // MARK: - UI Builder Helpers

    private func buildActionRow(title: String, description: String, pill: KeyPill, action: Selector, in stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        textStack.addArrangedSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        textStack.addArrangedSubview(descLabel)

        row.addArrangedSubview(textStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        pill.translatesAutoresizingMaskIntoConstraints = false
        let click = NSClickGestureRecognizer(target: self, action: action)
        pill.addGestureRecognizer(click)
        row.addArrangedSubview(pill)

        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildGamepadActionRow(title: String, statusLabel: NSTextField, defaultStatus: String,
                                        pill: KeyPill, action: Selector, in stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        textStack.addArrangedSubview(titleLabel)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = defaultStatus
        textStack.addArrangedSubview(statusLabel)

        row.addArrangedSubview(textStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        pill.translatesAutoresizingMaskIntoConstraints = false
        let click = NSClickGestureRecognizer(target: self, action: action)
        pill.addGestureRecognizer(click)
        row.addArrangedSubview(pill)

        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let iv = NSImageView(image: img)
            iv.symbolConfiguration = .init(pointSize: 13, weight: .medium)
            iv.contentTintColor = .secondaryLabelColor
            row.addArrangedSubview(iv)
        }

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        row.addArrangedSubview(label)

        return row
    }

    private func separator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        return sep
    }

    private func applySettings() {
        // Keyboard pills
        holdKeyPill.text = settings.holdModifier.displayName
        toggleKeyPill.text = settings.toggleModifier.displayName
        sendKeyPill.text = settings.sendModifier.displayName

        // ASR
        providerSegment.selectedSegment = settings.asrProvider.rawValue
        endpointField.stringValue = settings.asrEndpoint
        endpointField.placeholderString = settings.asrProvider.defaultEndpoint
        modelField.stringValue = settings.asrModel
        modelField.placeholderString = settings.asrProvider.defaultModel
        apiKeyField.stringValue = settings.activeApiKey
        apiKeyRow.isHidden = !settings.asrProvider.needsApiKey
        updateHelpLabel()
        refreshInputDevices()

        // Gamepad
        let gpEnabled = settings.gamepadEnabled
        gamepadToggleSwitch.state = gpEnabled ? .on : .off
        gamepadHoldPill.text = settings.gamepadHoldButton.displayName
        gamepadTogglePill.text = settings.gamepadToggleButton.displayName
        gamepadSendPill.text = settings.gamepadSendButton.displayName

        gamepadHoldPill.isHidden = !gpEnabled
        gamepadHoldStatusLabel.isHidden = !gpEnabled
        gamepadTogglePill.isHidden = !gpEnabled
        gamepadToggleStatusLabel.isHidden = !gpEnabled
        gamepadSendPill.isHidden = !gpEnabled
        gamepadSendStatusLabel.isHidden = !gpEnabled
    }

    private func refreshInputDevices() {
        inputDevices = AudioDevice.allInputDevices()
        inputDevicePopup.removeAllItems()
        inputDevicePopup.addItem(withTitle: "System Default")
        for device in inputDevices {
            inputDevicePopup.addItem(withTitle: device.name)
        }
        // Select the saved device
        if settings.inputDeviceID == 0 {
            inputDevicePopup.selectItem(at: 0)
        } else if let idx = inputDevices.firstIndex(where: { $0.id == settings.inputDeviceID }) {
            inputDevicePopup.selectItem(at: idx + 1)  // +1 for "System Default"
        } else {
            inputDevicePopup.selectItem(at: 0)
        }
    }

    @objc private func gamepadToggleChanged() {
        settings.gamepadEnabled = (gamepadToggleSwitch.state == .on)
        let gpEnabled = settings.gamepadEnabled
        gamepadHoldPill.isHidden = !gpEnabled
        gamepadHoldStatusLabel.isHidden = !gpEnabled
        gamepadTogglePill.isHidden = !gpEnabled
        gamepadToggleStatusLabel.isHidden = !gpEnabled
        gamepadSendPill.isHidden = !gpEnabled
        gamepadSendStatusLabel.isHidden = !gpEnabled
        saveAndNotify()
    }

    // MARK: - Keyboard Key Capture

    @objc private func startHoldKeyCapture() {
        startKeyCapture(target: .holdKey, pill: holdKeyPill)
    }

    @objc private func startToggleKeyCapture() {
        startKeyCapture(target: .toggleKey, pill: toggleKeyPill)
    }

    @objc private func startSendKeyCapture() {
        startKeyCapture(target: .sendKey, pill: sendKeyPill)
    }

    private func startKeyCapture(target: CaptureTarget, pill: KeyPill) {
        stopCapture()
        activeCaptureTarget = target
        pill.isCapturing = true
        pill.text = "按键... (Esc清除)"

        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }

            // Escape clears to none
            if event.type == .keyDown && event.keyCode == 53 {
                self.finishKeyCapture(modifier: .none)
                return nil
            }

            // Only handle flagsChanged for modifier keys
            if event.type == .flagsChanged, let modifier = ModifierKeySpec.fromEvent(event) {
                self.finishKeyCapture(modifier: modifier)
                return nil
            }

            return event
        }
    }

    private func finishKeyCapture(modifier: ModifierKeySpec) {
        guard let target = activeCaptureTarget else { return }

        // Check for conflicts with other keyboard modifiers (skip .none)
        if modifier.rawValue != 0 {
            let actionNames: [(CaptureTarget, ModifierKeySpec, String)] = [
                (.holdKey, settings.holdModifier, "按住说话"),
                (.toggleKey, settings.toggleModifier, "切换录音"),
                (.sendKey, settings.sendModifier, "发送"),
            ]
            for (otherTarget, otherModifier, otherName) in actionNames {
                if !isSameTarget(target, otherTarget) && modifier == otherModifier {
                    // Conflict
                    let pill = pillForTarget(target)
                    pill.isCapturing = false
                    pill.text = currentModifierForTarget(target).displayName
                    stopCapture()
                    // Brief flash of conflict message - use an alert
                    let alert = NSAlert()
                    alert.messageText = "快捷键冲突"
                    alert.informativeText = "\(modifier.displayName) 已被「\(otherName)」使用"
                    alert.alertStyle = .warning
                    alert.runModal()
                    return
                }
            }
        }

        // Apply the modifier
        switch target {
        case .holdKey:
            settings.holdModifierRawValue = modifier.rawValue
            settings.holdModifierName = modifier.displayName
            holdKeyPill.text = modifier.displayName
            holdKeyPill.isCapturing = false
        case .toggleKey:
            settings.toggleModifierRawValue = modifier.rawValue
            settings.toggleModifierName = modifier.displayName
            toggleKeyPill.text = modifier.displayName
            toggleKeyPill.isCapturing = false
        case .sendKey:
            settings.sendModifierRawValue = modifier.rawValue
            settings.sendModifierName = modifier.displayName
            sendKeyPill.text = modifier.displayName
            sendKeyPill.isCapturing = false
        default:
            break
        }

        stopCapture()
        saveAndNotify()
    }

    private func isSameTarget(_ a: CaptureTarget, _ b: CaptureTarget) -> Bool {
        switch (a, b) {
        case (.holdKey, .holdKey), (.toggleKey, .toggleKey), (.sendKey, .sendKey),
             (.gamepadHold, .gamepadHold), (.gamepadToggle, .gamepadToggle), (.gamepadSend, .gamepadSend):
            return true
        default:
            return false
        }
    }

    private func pillForTarget(_ target: CaptureTarget) -> KeyPill {
        switch target {
        case .holdKey: return holdKeyPill
        case .toggleKey: return toggleKeyPill
        case .sendKey: return sendKeyPill
        case .gamepadHold: return gamepadHoldPill
        case .gamepadToggle: return gamepadTogglePill
        case .gamepadSend: return gamepadSendPill
        }
    }

    private func currentModifierForTarget(_ target: CaptureTarget) -> ModifierKeySpec {
        switch target {
        case .holdKey: return settings.holdModifier
        case .toggleKey: return settings.toggleModifier
        case .sendKey: return settings.sendModifier
        default: return .none
        }
    }

    private func stopCapture() {
        if let m = captureMonitor {
            NSEvent.removeMonitor(m)
            captureMonitor = nil
        }
        activeCaptureTarget = nil
    }

    // MARK: - Gamepad Capture

    @objc private func startGamepadHoldCapture() {
        startGamepadCapture(target: .gamepadHold, pill: gamepadHoldPill, statusLabel: gamepadHoldStatusLabel)
    }

    @objc private func startGamepadToggleCapture() {
        startGamepadCapture(target: .gamepadToggle, pill: gamepadTogglePill, statusLabel: gamepadToggleStatusLabel)
    }

    @objc private func startGamepadSendCapture() {
        startGamepadCapture(target: .gamepadSend, pill: gamepadSendPill, statusLabel: gamepadSendStatusLabel)
    }

    private func startGamepadCapture(target: CaptureTarget, pill: KeyPill, statusLabel: NSTextField) {
        stopGamepadCapture()
        guard let monitor = gamepadMonitor, monitor.isConnected else {
            statusLabel.stringValue = "未检测到手柄，请先连接"
            statusLabel.textColor = .systemRed
            return
        }
        activeCaptureTarget = target
        pill.isCapturing = true
        pill.text = "按手柄按键..."
        statusLabel.stringValue = "等待手柄输入..."
        statusLabel.textColor = .controlAccentColor

        monitor.onButtonCaptured = { [weak self] button in
            self?.finishGamepadCapture(button: button)
        }
        monitor.startCapture()
    }

    private func finishGamepadCapture(button: GamepadButton) {
        guard let target = activeCaptureTarget else { return }

        // Check for conflicts with other gamepad buttons (skip .none)
        if button != .none {
            let actionNames: [(CaptureTarget, GamepadButton, String)] = [
                (.gamepadHold, settings.gamepadHoldButton, "按住说话"),
                (.gamepadToggle, settings.gamepadToggleButton, "切换录音"),
                (.gamepadSend, settings.gamepadSendButton, "发送"),
            ]
            for (otherTarget, otherButton, otherName) in actionNames {
                if !isSameTarget(target, otherTarget) && button == otherButton {
                    let pill = pillForTarget(target)
                    let statusLabel = gamepadStatusLabelForTarget(target)
                    pill.isCapturing = false
                    pill.text = currentGamepadButtonForTarget(target).displayName
                    statusLabel.stringValue = "与「\(otherName)」冲突"
                    statusLabel.textColor = .systemRed
                    gamepadMonitor?.stopCapture()
                    activeCaptureTarget = nil
                    return
                }
            }
        }

        let statusLabel = gamepadStatusLabelForTarget(target)

        switch target {
        case .gamepadHold:
            settings.gamepadHoldButton = button
            gamepadHoldPill.text = button.displayName
            gamepadHoldPill.isCapturing = false
            statusLabel.stringValue = "已设置为 \(button.displayName) 按钮"
        case .gamepadToggle:
            settings.gamepadToggleButton = button
            gamepadTogglePill.text = button.displayName
            gamepadTogglePill.isCapturing = false
            statusLabel.stringValue = "已设置为 \(button.displayName) 按钮"
        case .gamepadSend:
            settings.gamepadSendButton = button
            gamepadSendPill.text = button.displayName
            gamepadSendPill.isCapturing = false
            statusLabel.stringValue = "已设置为 \(button.displayName) 按钮"
        default:
            break
        }

        statusLabel.textColor = .secondaryLabelColor
        activeCaptureTarget = nil
        saveAndNotify()
    }

    private func gamepadStatusLabelForTarget(_ target: CaptureTarget) -> NSTextField {
        switch target {
        case .gamepadHold: return gamepadHoldStatusLabel
        case .gamepadToggle: return gamepadToggleStatusLabel
        case .gamepadSend: return gamepadSendStatusLabel
        default: return gamepadHoldStatusLabel
        }
    }

    private func currentGamepadButtonForTarget(_ target: CaptureTarget) -> GamepadButton {
        switch target {
        case .gamepadHold: return settings.gamepadHoldButton
        case .gamepadToggle: return settings.gamepadToggleButton
        case .gamepadSend: return settings.gamepadSendButton
        default: return .none
        }
    }

    private func stopGamepadCapture() {
        gamepadMonitor?.stopCapture()
        gamepadHoldPill.isCapturing = false
        gamepadTogglePill.isCapturing = false
        gamepadSendPill.isCapturing = false
    }

    @objc private func inputDeviceChanged() {
        let idx = inputDevicePopup.indexOfSelectedItem
        if idx == 0 {
            settings.inputDeviceID = 0
        } else {
            settings.inputDeviceID = inputDevices[idx - 1].id
        }
        saveAndNotify()
    }

    private func updateHelpLabel() {
        let provider = settings.asrProvider
        let text = NSMutableAttributedString()

        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        text.append(NSAttributedString(string: provider.helpText, attributes: descAttrs))

        if let linkTitle = provider.helpLinkTitle, let urlString = provider.helpLinkURL,
           let url = URL(string: urlString) {
            text.append(NSAttributedString(string: "\n", attributes: descAttrs))
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.controlAccentColor,
                .link: url,
                .cursor: NSCursor.pointingHand
            ]
            text.append(NSAttributedString(string: linkTitle, attributes: linkAttrs))
        }

        helpLabel.attributedStringValue = text
    }

    private func saveAndNotify() {
        settings.save()
        onChange(settings)
    }

    // MARK: - Provider switch

    @objc private func providerChanged() {
        // Save current API key before switching
        saveApiKeyForCurrentProvider()
        let provider = ASRProvider(rawValue: providerSegment.selectedSegment) ?? .local
        settings.asrProvider = provider
        settings.asrEndpoint = provider.defaultEndpoint
        settings.asrModel = provider.defaultModel
        applySettings()
        saveAndNotify()
    }

    private func saveApiKeyForCurrentProvider() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch settings.asrProvider {
        case .groq: settings.groqApiKey = key
        case .gemini: settings.geminiApiKey = key
        case .local, .funasrStreaming: break
        }
    }

    // MARK: - Endpoint auto-save

    func controlTextDidEndEditing(_ obj: Notification) {
        let endpoint = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.asrEndpoint = endpoint.isEmpty ? settings.asrProvider.defaultEndpoint : endpoint

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.asrModel = model.isEmpty ? settings.asrProvider.defaultModel : model

        saveApiKeyForCurrentProvider()

        saveAndNotify()
    }

    // MARK: - Test

    @objc private func testConnection() {
        // Sync fields to settings before testing (user may not have tabbed out)
        window?.makeFirstResponder(nil)
        let ep = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.asrEndpoint = ep.isEmpty ? settings.asrProvider.defaultEndpoint : ep
        let mdl = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.asrModel = mdl.isEmpty ? settings.asrProvider.defaultModel : mdl
        saveApiKeyForCurrentProvider()
        saveAndNotify()

        testButton.isEnabled = false
        testStatusLabel.stringValue = "Testing..."
        testStatusLabel.textColor = .secondaryLabelColor

        if settings.asrProvider == .funasrStreaming {
            testFunASRConnection()
            return
        }

        let silentWAV = buildSilentWAV(durationMs: 500)

        let request: URLRequest
        switch settings.asrProvider {
        case .gemini:
            guard let r = buildGeminiTestRequest(wav: silentWAV) else {
                showTestResult(success: false, message: "Invalid Gemini URL")
                return
            }
            request = r
        case .local, .groq:
            guard let r = buildOpenAITestRequest(wav: silentWAV) else {
                showTestResult(success: false, message: "Invalid URL")
                return
            }
            request = r
        case .funasrStreaming:
            return // handled above
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showTestResult(success: false, message: error.localizedDescription)
                } else if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self?.showTestResult(success: true, message: "Connection OK (HTTP 200)")
                } else if let http = response as? HTTPURLResponse {
                    let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    self?.showTestResult(success: false, message: "HTTP \(http.statusCode) \(detail.prefix(80))")
                } else {
                    self?.showTestResult(success: false, message: "No response")
                }
            }
        }.resume()
    }

    private func showTestResult(success: Bool, message: String) {
        testButton.isEnabled = true
        testStatusLabel.stringValue = message
        testStatusLabel.textColor = success ? .systemGreen : .systemRed
    }

    private var testWebSocketTask: URLSessionWebSocketTask?

    private func testFunASRConnection() {
        guard let url = URL(string: settings.asrEndpoint) else {
            showTestResult(success: false, message: "Invalid WebSocket URL")
            return
        }

        let task = URLSession.shared.webSocketTask(with: url)
        testWebSocketTask = task
        task.resume()

        let config: [String: Any] = [
            "mode": settings.asrModel,
            "wav_name": "test",
            "is_speaking": true,
            "wav_format": "pcm",
            "audio_fs": 16000,
            "chunk_size": [5, 10, 5]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            showTestResult(success: false, message: "Failed to build config JSON")
            return
        }

        task.send(.string(jsonString)) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showTestResult(success: false, message: error.localizedDescription)
                } else {
                    self?.showTestResult(success: true, message: "WebSocket connected OK")
                }
                // Send end signal and close
                let end = "{\"is_speaking\": false}"
                task.send(.string(end)) { _ in
                    task.cancel(with: .normalClosure, reason: nil)
                }
                self?.testWebSocketTask = nil
            }
        }
    }

    private func buildOpenAITestRequest(wav: Data) -> URLRequest? {
        guard let url = URL(string: settings.asrEndpoint) else { return nil }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let activeKey = settings.activeApiKey
        if !activeKey.isEmpty {
            request.setValue("Bearer \(activeKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"test.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(settings.asrModel.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return request
    }

    private func buildGeminiTestRequest(wav: Data) -> URLRequest? {
        let urlString = "\(settings.asrEndpoint)/models/\(settings.asrModel):generateContent?key=\(settings.activeApiKey)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "audio/wav", "data": wav.base64EncodedString()]],
                    ["text": "Transcribe this audio exactly. Output ONLY the spoken words, nothing else. Do NOT include timestamps, speaker labels, time codes, or any formatting. Preserve the original language."]
                ]
            ]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func buildSilentWAV(durationMs: Int) -> Data {
        let sampleRate = 16000
        let numSamples = sampleRate * durationMs / 1000
        let dataSize = numSamples * 2
        var d = Data(capacity: 44 + dataSize)

        func u32(_ v: UInt32) { var v = v; d.append(Data(bytes: &v, count: 4)) }
        func u16(_ v: UInt16) { var v = v; d.append(Data(bytes: &v, count: 2)) }

        d.append(contentsOf: "RIFF".utf8); u32(UInt32(36 + dataSize))
        d.append(contentsOf: "WAVE".utf8)
        d.append(contentsOf: "fmt ".utf8); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: "data".utf8); u32(UInt32(dataSize))
        d.append(Data(count: dataSize)) // silence
        return d
    }
}
