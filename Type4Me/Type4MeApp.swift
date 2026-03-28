import SwiftUI

@main
struct Type4MeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra(
            "VoiceInput",
            systemImage: appDelegate.appState.barPhase == .hidden ? "mic" : "mic.fill"
        ) {
            MenuBarContent()
                .environment(appDelegate.appState)
        }

        Window(L("VoiceInput 设置", "VoiceInput Settings"), id: "settings") {
            SettingsView()
                .environment(appDelegate.appState)
        }
        .defaultSize(width: 1200, height: 800)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)

        Window(L("VoiceInput 设置向导", "VoiceInput Setup"), id: "setup") {
            SetupWizardView()
                .environment(appDelegate.appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private let startSoundDelay: Duration = .milliseconds(200)
    private var floatingBarController: FloatingBarController?
    private let hotkeyManager = HotkeyManager()
    private let gamepadMonitor = GamepadMonitor(
        holdButton: GamepadButton.savedHoldButton,
        toggleButton: GamepadButton.savedToggleButton,
        sendButton: GamepadButton.savedSendButton
    )
    private let session = RecognitionSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchT0 = CFAbsoluteTimeGetCurrent()
        NSLog("[Type4Me] applicationDidFinishLaunching")
        DebugFileLogger.startSession()
        DebugFileLogger.log("applicationDidFinishLaunching")

        var t0 = CFAbsoluteTimeGetCurrent()
        KeychainService.migrateIfNeeded()
        var ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] KeychainService.migrateIfNeeded: \(ms)ms")

        t0 = CFAbsoluteTimeGetCurrent()
        HotwordStorage.seedIfNeeded()
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] HotwordStorage.seedIfNeeded: \(ms)ms")

        t0 = CFAbsoluteTimeGetCurrent()
        floatingBarController = FloatingBarController(state: appState)
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] FloatingBarController init: \(ms)ms")

        // Bridge ASR events → AppState for floating bar display
        let session = self.session

        // 历史记录字数迁移（用 session 自带的 historyStore，迁移后 UI 能刷新）
        Task {
            let taskT0 = CFAbsoluteTimeGetCurrent()
            await session.historyStore.migrateCharacterCounts()
            let taskMs = Int((CFAbsoluteTimeGetCurrent() - taskT0) * 1000)
            DebugFileLogger.log("[PERF] historyStore.migrateCharacterCounts: \(taskMs)ms")
        }
        let appState = self.appState
        let startSoundDelay = self.startSoundDelay

        t0 = CFAbsoluteTimeGetCurrent()
        SoundFeedback.warmUp()
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] SoundFeedback.warmUp: \(ms)ms")

        // Pre-warm audio subsystem so the first recording starts instantly
        Task {
            let taskT0 = CFAbsoluteTimeGetCurrent()
            await session.warmUp()
            let taskMs = Int((CFAbsoluteTimeGetCurrent() - taskT0) * 1000)
            DebugFileLogger.log("[PERF] session.warmUp: \(taskMs)ms")
        }

        // Bridge audio level → isolated meter (no SwiftUI observation overhead)
        Task {
            await session.setOnAudioLevel { level in
                Task { @MainActor in
                    appState.audioLevel.current = level
                }
            }
        }

        Task {
            await session.setOnASREvent { event in
                Task { @MainActor in
                    switch event {
                    case .ready:
                        NSLog("[Type4Me] ready event received")
                        DebugFileLogger.log("ready event received, current barPhase=\(String(describing: appState.barPhase))")
                        appState.markRecordingReady()
                        Task { @MainActor in
                            NSLog("[Type4Me] playStart scheduled")
                            DebugFileLogger.log("playStart scheduled delayMs=200")
                            try? await Task.sleep(for: startSoundDelay)
                            guard appState.barPhase == .recording else {
                                DebugFileLogger.log("playStart aborted, barPhase=\(String(describing: appState.barPhase))")
                                return
                            }
                            NSLog("[Type4Me] playStart firing")
                            DebugFileLogger.log("playStart firing")
                            SoundFeedback.playStart()
                        }
                    case .transcript(let transcript):
                        appState.setLiveTranscript(transcript)
                    case .completed:
                        appState.stopRecording()
                    case .processingResult(let text):
                        appState.showProcessingResult(text)
                    case .finalized(let text, let injection):
                        appState.finalize(text: text, outcome: injection)
                    case .error(let error):
                        appState.showError(self.userFacingMessage(for: error))
                    }
                }
            }
        }

        // Start periodic update checking
        t0 = CFAbsoluteTimeGetCurrent()
        UpdateChecker.shared.startPeriodicChecking(appState: appState)
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] UpdateChecker.startPeriodicChecking: \(ms)ms")

        // Reconcile current mode against the active provider before hotkeys are registered.
        t0 = CFAbsoluteTimeGetCurrent()
        refreshModeAvailability()
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] refreshModeAvailability: \(ms)ms")

        // Re-register when modes change in Settings
        NotificationCenter.default.addObserver(
            forName: .modesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshModeAvailability()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .asrProviderDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshModeAvailability()
            }
        }

        // Suppress/resume hotkeys during hotkey recording
        NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.hotkeyManager.isSuppressed = true
            }
        }
        NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.hotkeyManager.isSuppressed = false
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hotkeyT0 = CFAbsoluteTimeGetCurrent()
            self.startHotkeyWithRetry()
            let hotkeyMs = Int((CFAbsoluteTimeGetCurrent() - hotkeyT0) * 1000)
            DebugFileLogger.log("[PERF] startHotkeyWithRetry: \(hotkeyMs)ms")
        }

        // Start gamepad monitoring
        t0 = CFAbsoluteTimeGetCurrent()
        setupGamepadMonitor()
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] setupGamepadMonitor: \(ms)ms")

        // Show setup wizard on first launch
        if !appState.hasCompletedSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    _ = NSApp.sendAction(Selector(("showSetupWindow:")), to: nil, from: nil)
                }
            }
        }

        // Check if menu bar icon is hidden by macOS 26+ "Allow in Menu Bar" setting
        t0 = CFAbsoluteTimeGetCurrent()
        checkMenuBarVisibility()
        ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        DebugFileLogger.log("[PERF] checkMenuBarVisibility: \(ms)ms")

        // Dynamic activation policy: show dock icon when windows are open
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleManagedWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleManagedWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - launchT0) * 1000)
        DebugFileLogger.log("[PERF] total startup: \(totalMs)ms")
    }

    private func refreshModeAvailability() {
        let provider = KeychainService.selectedASRProvider
        appState.reconcileCurrentMode(for: provider)
        registerHotkeys(for: provider)
    }

    private func registerHotkeys(for provider: ASRProvider) {
        let availableModes = appState.availableModes
        let modes = ASRProviderRegistry.supportedModes(from: availableModes, for: provider)
        let bindings: [ModeBinding] = modes.compactMap { mode in
            guard let code = mode.hotkeyCode else { return nil }
            let modifiers = CGEventFlags(rawValue: mode.hotkeyModifiers ?? 0)
            let capturedMode = mode
            return ModeBinding(
                modeId: mode.id,
                keyCode: CGKeyCode(code),
                modifiers: modifiers,
                style: capturedMode.hotkeyStyle,
                onStart: { [weak self] in
                    guard let self else { return }
                    let selectedProvider = KeychainService.selectedASRProvider
                    let resolvedMode = ASRProviderRegistry.resolvedMode(for: capturedMode, provider: selectedProvider)
                    let effectiveMode = availableModes.first(where: { $0.id == resolvedMode.id }) ?? resolvedMode
                    NSLog("[Type4Me] >>> HOTKEY: Record START (mode: %@)", effectiveMode.name)
                    DebugFileLogger.log("hotkey record start mode=\(effectiveMode.name)")
                    Task { @MainActor in
                        self.appState.currentMode = effectiveMode
                        self.appState.startRecording()
                    }
                    Task { await self.session.startRecording(mode: effectiveMode) }
                },
                onStop: { [weak self] in
                    guard let self else { return }
                    NSLog("[Type4Me] >>> HOTKEY: Record STOP")
                    DebugFileLogger.log("hotkey record stop")
                    Task { @MainActor in self.appState.stopRecording() }
                    Task { await self.session.stopRecording() }
                }
            )
        }
        hotkeyManager.registerBindings(bindings)

        // Cross-mode stop: user pressed mode B's key while mode A was recording.
        // Switch to mode B and stop, so the recording is processed with mode B.
        hotkeyManager.onCrossModeStop = { [weak self] newModeId in
            guard let self else { return }
            guard let newMode = availableModes.first(where: { $0.id == newModeId }) else { return }
            let selectedProvider = KeychainService.selectedASRProvider
            let resolvedMode = ASRProviderRegistry.resolvedMode(for: newMode, provider: selectedProvider)
            let effectiveMode = availableModes.first(where: { $0.id == resolvedMode.id }) ?? resolvedMode
            NSLog("[Type4Me] >>> HOTKEY: Cross-mode stop → %@", effectiveMode.name)
            DebugFileLogger.log("hotkey cross-mode stop → \(effectiveMode.name)")
            Task { @MainActor in
                self.appState.currentMode = effectiveMode
                self.appState.stopRecording()
            }
            Task {
                await self.session.switchMode(to: effectiveMode)
                await self.session.stopRecording()
            }
        }
    }

    private var retryTimer: Timer?

    private func startHotkeyWithRetry() {
        let success = hotkeyManager.start()
        NSLog("[Type4Me] Hotkey setup: %@", success ? "OK" : "FAILED (need Accessibility permission)")

        if success {
            retryTimer?.invalidate()
            retryTimer = nil
            return
        }

        // Prompt for accessibility and poll until granted
        PermissionManager.promptAccessibilityPermission()
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(handleHotkeyRetry(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func handleHotkeyRetry(_ timer: Timer) {
        if PermissionManager.hasAccessibilityPermission {
            let ok = hotkeyManager.start()
            NSLog("[Type4Me] Hotkey retry: %@", ok ? "OK" : "still failing")
            if ok {
                timer.invalidate()
                retryTimer = nil
            }
        }
    }

    // MARK: - Gamepad Monitor

    private func setupGamepadMonitor() {
        // Expose the monitor to the Settings UI
        GamepadSettingsCard.sharedMonitor = gamepadMonitor

        let session = self.session
        let appState = self.appState

        // Hold button: press to start recording, release to stop
        gamepadMonitor.onHoldStart = { [weak self] in
            guard self != nil else { return }
            let selectedProvider = KeychainService.selectedASRProvider
            let modes = appState.availableModes
            let resolvedMode = ASRProviderRegistry.resolvedMode(
                for: appState.currentMode, provider: selectedProvider
            )
            let effectiveMode = modes.first(where: { $0.id == resolvedMode.id }) ?? resolvedMode
            NSLog("[Type4Me] >>> GAMEPAD: Hold START (mode: %@)", effectiveMode.name)
            DebugFileLogger.log("gamepad hold start mode=\(effectiveMode.name)")
            Task { @MainActor in
                appState.currentMode = effectiveMode
                appState.startRecording()
            }
            Task {
                await session.setAppendNewline(true)
                await session.startRecording(mode: effectiveMode)
            }
        }

        gamepadMonitor.onHoldEnd = { [weak self] in
            guard self != nil else { return }
            NSLog("[Type4Me] >>> GAMEPAD: Hold STOP")
            DebugFileLogger.log("gamepad hold stop")
            Task { @MainActor in appState.stopRecording() }
            Task { await session.stopRecording() }
        }

        // Toggle button: tap to start/stop
        gamepadMonitor.onToggleTap = { [weak self] in
            guard self != nil else { return }
            let isRecording = appState.barPhase == .recording || appState.barPhase == .preparing
            if isRecording {
                NSLog("[Type4Me] >>> GAMEPAD: Toggle STOP")
                DebugFileLogger.log("gamepad toggle stop")
                Task { @MainActor in appState.stopRecording() }
                Task { await session.stopRecording() }
            } else {
                let selectedProvider = KeychainService.selectedASRProvider
                let modes = appState.availableModes
                let resolvedMode = ASRProviderRegistry.resolvedMode(
                    for: appState.currentMode, provider: selectedProvider
                )
                let effectiveMode = modes.first(where: { $0.id == resolvedMode.id }) ?? resolvedMode
                NSLog("[Type4Me] >>> GAMEPAD: Toggle START (mode: %@)", effectiveMode.name)
                DebugFileLogger.log("gamepad toggle start mode=\(effectiveMode.name)")
                Task { @MainActor in
                    appState.currentMode = effectiveMode
                    appState.startRecording()
                }
                Task { await session.startRecording(mode: effectiveMode) }
            }
        }

        // Send button: currently unused, reserved for future use
        gamepadMonitor.onSendTap = {
            NSLog("[Type4Me] >>> GAMEPAD: Send TAP (no-op)")
        }

        // Listen for gamepad button config changes from Settings UI
        NotificationCenter.default.addObserver(
            forName: .gamepadConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.gamepadMonitor.updateHoldButton(GamepadButton.savedHoldButton)
                self.gamepadMonitor.updateToggleButton(GamepadButton.savedToggleButton)
                self.gamepadMonitor.updateSendButton(GamepadButton.savedSendButton)
                NSLog("[Type4Me] Gamepad buttons updated: hold=%@, toggle=%@, send=%@",
                      GamepadButton.savedHoldButton.displayName,
                      GamepadButton.savedToggleButton.displayName,
                      GamepadButton.savedSendButton.displayName)
            }
        }

        gamepadMonitor.start()
    }

    @objc
    private func handleManagedWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "settings" ||
              window.identifier?.rawValue == "setup" ||
              window.title.contains("VoiceInput") else { return }
        NSApp.setActivationPolicy(.regular)
    }

    @objc
    private func handleManagedWindowWillClose(_ notification: Notification) {
        Timer.scheduledTimer(
            timeInterval: 0.3,
            target: self,
            selector: #selector(updateActivationPolicyAfterWindowClose(_:)),
            userInfo: nil,
            repeats: false
        )
    }

    @objc
    private func updateActivationPolicyAfterWindowClose(_ timer: Timer) {
        let hasVisibleWindow = NSApp.windows.contains {
            $0.isVisible && !$0.className.contains("StatusBar") && !$0.className.contains("Panel")
            && $0.level == .normal
        }
        if !hasVisibleWindow {
            NSApp.setActivationPolicy(.accessory)
            // Resign active so menu bar or previous app gets focus
            NSApp.hide(nil)
        }
    }

    // MARK: - Menu Bar Visibility Check (macOS 26+)

    private static let menuBarCheckKey = "tf_menuBarHiddenAlertShown"

    /// On macOS 26 Tahoe, System Settings > Menu Bar > "Allow in Menu Bar" can hide
    /// third-party status items by rendering them offscreen. Detect this and alert the user.
    private func checkMenuBarVisibility() {
        // Only check on macOS 26+ where this feature exists
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return }
        // Don't nag repeatedly — only alert once per app version
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let shownForVersion = UserDefaults.standard.string(forKey: Self.menuBarCheckKey)
        guard shownForVersion != currentVersion else { return }

        // Delay to give SwiftUI MenuBarExtra time to create the status item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.performMenuBarCheck(version: currentVersion)
            }
        }
    }

    private func performMenuBarCheck(version: String) {
        // Find status bar windows belonging to our app.
        // SwiftUI's MenuBarExtra creates an NSStatusBarWindow with a button inside.
        let statusBarWindows = NSApp.windows.filter {
            $0.className.contains("NSStatusBar")
        }

        let isVisible: Bool
        if statusBarWindows.isEmpty {
            // No status bar window at all — icon wasn't created
            isVisible = false
        } else {
            // Check if any status bar window is in a reasonable screen position.
            // macOS 26 moves hidden items far offscreen (e.g. y < -10000).
            let screenFrame = NSScreen.main?.frame ?? .zero
            isVisible = statusBarWindows.contains { window in
                let frame = window.frame
                return frame.origin.x >= -100
                    && frame.origin.x <= screenFrame.width + 100
                    && frame.origin.y >= -100
            }
        }

        guard !isVisible else { return }

        NSLog("[Type4Me] Menu bar icon appears hidden by system settings")

        // Remember we showed this alert for this version
        UserDefaults.standard.set(version, forKey: Self.menuBarCheckKey)

        let alert = NSAlert()
        alert.messageText = L(
            "菜单栏图标被隐藏",
            "Menu Bar Icon Hidden"
        )
        alert.informativeText = L(
            "macOS 的菜单栏设置可能隐藏了 VoiceInput 图标。\n\n请前往 系统设置 > 菜单栏，在「允许在菜单栏中显示」列表中开启 VoiceInput。",
            "macOS may have hidden the VoiceInput icon.\n\nGo to System Settings > Menu Bar and enable VoiceInput in the 'Allow in Menu Bar' list."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("打开系统设置", "Open System Settings"))
        alert.addButton(withTitle: L("稍后处理", "Later"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open Menu Bar settings (macOS 26+)
            if let url = URL(string: "x-apple.systempreferences:com.apple.MenuBar-Settings") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let captureError = error as? AudioCaptureError,
           let description = captureError.errorDescription {
            return description
        }

        let nsError = error as NSError
        if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        return L("录音启动失败", "Failed to start recording")
    }
}

// MARK: - Menu Bar Content

struct MenuBarContent: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openWindow) private var openSettingsWindow
    @AppStorage("tf_language") private var language = AppLanguage.systemDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }

        Divider()

        // Mode hotkey hints (click to open settings)
        ForEach(appState.availableModes) { mode in
            Button {
                openSettingsWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(
                    name: .navigateToMode, object: mode.id
                )
            } label: {
                let hotkey = mode.hotkeyCode.map {
                    HotkeyRecorderView.keyDisplayName(keyCode: $0, modifiers: mode.hotkeyModifiers)
                }
                Text("\(mode.name)  [\(hotkey ?? L("未绑定", "Unbound"))]")
            }
        }

        Divider()

        Button(L("设置向导...", "Setup Wizard...")) {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "setup")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button(L("偏好设置...", "Preferences...")) {
            NSApp.setActivationPolicy(.regular)
            openSettingsWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(L("退出 VoiceInput", "Quit VoiceInput")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)

        // Force re-render when language changes
        let _ = language
    }

    private var statusColor: Color {
        switch appState.barPhase {
        case .preparing: return TF.recording
        case .recording: return TF.recording
        case .processing: return TF.amber
        case .done: return TF.success
        case .error: return TF.settingsAccentRed
        case .hidden: return .secondary.opacity(0.4)
        }
    }

    private var statusText: String {
        switch appState.barPhase {
        case .preparing: return L("录制中", "Recording")
        case .recording: return L("录制中", "Recording")
        case .processing: return appState.currentMode.processingLabel
        case .done: return L("完成", "Done")
        case .error: return L("错误", "Error")
        case .hidden: return L("就绪", "Ready")
        }
    }
}
