import AppKit

extension String {
    func appendToFile(_ path: String) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try write(toFile: path, atomically: true, encoding: .utf8)
        } else if let data = data(using: .utf8), let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var keyMonitor: KeyMonitor!
    private var gamepadMonitor: GamepadMonitor?
    private var audioRecorder: AudioRecorder!
    private var asrClient: ASRClient!
    private var overlayWindow: OverlayWindow!
    private var settingsWindowController: SettingsWindowController?
    private var funasrClient: FunASRStreamingClient?
    private var settings = AppSettings.load()
    private var isRecording = false
    private var pendingAutoSend = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? "VoiceInput launched at \(Date())\n".write(toFile: "/tmp/voiceinput-debug.log", atomically: true, encoding: .utf8)
        NSApp.setActivationPolicy(.accessory)

        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceInput")
        }
        let menu = NSMenu()
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)
        menu.addItem(NSMenuItem.separator())
        let quitMenuItem = NSMenuItem(title: "Quit VoiceInput", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        statusItem.menu = menu

        // Components
        audioRecorder = AudioRecorder()
        if settings.inputDeviceID != 0 {
            audioRecorder.setInputDevice(settings.inputDeviceID)
        }
        audioRecorder.prepare()  // Pre-warm audio engine
        asrClient = ASRClient(endpoint: settings.asrEndpoint, modelName: settings.asrModel, apiKey: settings.activeApiKey, provider: settings.asrProvider)
        overlayWindow = OverlayWindow()

        audioRecorder.onLevels = { [weak self] levels in
            self?.overlayWindow.updateLevels(levels)
        }
        overlayWindow.onCancel = { [weak self] in
            self?.cancelRecording()
        }
        overlayWindow.onDone = { [weak self] in
            if self?.isRecording == true {
                self?.stopAndTranscribe()
            }
        }

        keyMonitor = KeyMonitor(
            holdModifier: settings.holdModifier,
            toggleModifier: settings.toggleModifier,
            sendModifier: settings.sendModifier,
            onHoldStart: { [weak self] in
                if !(self?.isRecording ?? true) { self?.startRecording() }
            },
            onHoldEnd: { [weak self] in
                if self?.isRecording ?? false { self?.stopAndTranscribe(autoSend: true) }
            },
            onToggle: { [weak self] in
                self?.toggle()
            },
            onSend: { [weak self] in
                self?.simulateEnter()
            }
        )
        keyMonitor.start()

        if settings.gamepadEnabled {
            startGamepadMonitor()
        }

        // Check accessibility permission and prompt if needed
        checkAccessibility()

        print("VoiceInput ready. Toggle=\(settings.toggleModifier.displayName), Hold=\(settings.holdModifier.displayName)")
    }

    private func toggle() {
        if isRecording { stopAndTranscribe() } else { startRecording() }
    }

    private func startRecording() {
        let t0 = CFAbsoluteTimeGetCurrent()
        isRecording = true
        overlayWindow.showRecording()
        let t1 = CFAbsoluteTimeGetCurrent()

        if settings.asrProvider.isStreaming {
            let client = FunASRStreamingClient(
                endpoint: settings.asrEndpoint,
                mode: settings.asrModel
            )
            client.onPartialResult = { [weak self] text in
                self?.overlayWindow.updatePartialTranscript(text)
            }
            client.onFinalResult = { [weak self] result in
                self?.handleStreamingResult(result)
            }
            self.funasrClient = client
            audioRecorder.onAudioBuffer = { [weak client] buffer in
                client?.sendAudioBuffer(buffer)
            }
            client.connect()
        }

        audioRecorder.start()
        let t2 = CFAbsoluteTimeGetCurrent()
        SoundFeedback.playStart()
        let t3 = CFAbsoluteTimeGetCurrent()
        let msg = String(format: "startRecording: showOverlay=%.1fms, audioStart=%.1fms, sound=%.1fms, total=%.1fms\n",
                         (t1-t0)*1000, (t2-t1)*1000, (t3-t2)*1000, (t3-t0)*1000)
        try? msg.appendToFile("/tmp/voiceinput-debug.log")
    }

    private func stopAndTranscribe(autoSend: Bool = false) {
        isRecording = false
        pendingAutoSend = autoSend
        overlayWindow.releaseKey()

        if settings.asrProvider.isStreaming {
            _ = audioRecorder.stop()
            audioRecorder.onAudioBuffer = nil
            overlayWindow.showProcessing()
            funasrClient?.finishSpeaking()
            // Final result comes via onFinalResult callback
            return
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        guard let audioData = audioRecorder.stop() else {
            try? "stopAndTranscribe: NO AUDIO DATA\n".appendToFile("/tmp/voiceinput-debug.log")
            overlayWindow.showError("No audio captured")
            pendingAutoSend = false
            return
        }
        try? "stopAndTranscribe: audioSize=\(audioData.count) bytes\n".appendToFile("/tmp/voiceinput-debug.log")
        overlayWindow.showProcessing()

        asrClient.transcribe(wavData: audioData) { [weak self] result in
            let t1 = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let text):
                    try? String(format: "ASR done: %.0fms, text=\"%@\"\n", (t1-t0)*1000, text).appendToFile("/tmp/voiceinput-debug.log")
                    self.paste(text: text)
                    self.overlayWindow.showSuccess(text)
                    if self.pendingAutoSend {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.simulateEnter()
                        }
                    }
                    self.pendingAutoSend = false
                case .failure(let error):
                    try? "ASR error: \(error.localizedDescription)\n".appendToFile("/tmp/voiceinput-debug.log")
                    self.overlayWindow.showError(error.localizedDescription)
                    self.pendingAutoSend = false
                }
            }
        }
    }

    private func handleStreamingResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let text):
            try? "FunASR streaming done: text=\"\(text)\"\n".appendToFile("/tmp/voiceinput-debug.log")
            paste(text: text)
            overlayWindow.showSuccess(text)
            if pendingAutoSend {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.simulateEnter()
                }
            }
            pendingAutoSend = false
        case .failure(let error):
            try? "FunASR streaming error: \(error.localizedDescription)\n".appendToFile("/tmp/voiceinput-debug.log")
            overlayWindow.showError(error.localizedDescription)
            pendingAutoSend = false
        }
        funasrClient = nil
    }

    private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingAutoSend = false
        _ = audioRecorder.stop()
        audioRecorder.onAudioBuffer = nil
        funasrClient?.disconnect()
        funasrClient = nil
        overlayWindow.hide()
    }

    private func paste(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        try? "paste: copied to clipboard, trusted=\(AXIsProcessTrusted())\n".appendToFile("/tmp/voiceinput-debug.log")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let src = CGEventSource(stateID: .privateState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            guard let down = vDown, let up = vUp else {
                try? "paste: CGEvent creation FAILED\n".appendToFile("/tmp/voiceinput-debug.log")
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try? "paste: Cmd+V posted, trusted=\(AXIsProcessTrusted())\n".appendToFile("/tmp/voiceinput-debug.log")
        }
    }

    private func startGamepadMonitor() {
        let monitor = GamepadMonitor(
            holdButton: settings.gamepadHoldButton,
            toggleButton: settings.gamepadToggleButton,
            sendButton: settings.gamepadSendButton
        )
        monitor.onHoldStart = { [weak self] in
            guard let self, !self.isRecording else { return }
            self.startRecording()
        }
        monitor.onHoldEnd = { [weak self] in
            guard let self, self.isRecording else { return }
            self.stopAndTranscribe(autoSend: true)
        }
        monitor.onToggleTap = { [weak self] in
            self?.toggle()
        }
        monitor.onSendTap = { [weak self] in
            self?.simulateEnter()
        }
        monitor.onConnectionChanged = { connected in
            try? "Gamepad \(connected ? "connected" : "disconnected")\n".appendToFile("/tmp/voiceinput-debug.log")
        }
        monitor.start()
        self.gamepadMonitor = monitor
        settingsWindowController?.updateGamepadMonitor(monitor)
    }

    private func simulateEnter() {
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func checkAccessibility() {
        // Silent check first
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // Only prompt if not trusted
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
            try? "checkAccessibility: NOT trusted, prompting user\n".appendToFile("/tmp/voiceinput-debug.log")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings, gamepadMonitor: gamepadMonitor) { [weak self] updated in
                self?.applySettings(updated)
            }
        }
        settingsWindowController?.update(settings: settings)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func applySettings(_ s: AppSettings) {
        self.settings = s
        keyMonitor.updateModifiers(hold: s.holdModifier, toggle: s.toggleModifier, send: s.sendModifier)
        asrClient.updateConfiguration(endpoint: s.asrEndpoint, modelName: s.asrModel, apiKey: s.activeApiKey, provider: s.asrProvider)
        audioRecorder.setInputDevice(s.inputDeviceID == 0 ? nil : s.inputDeviceID)

        if s.gamepadEnabled {
            if let monitor = gamepadMonitor {
                monitor.updateHoldButton(s.gamepadHoldButton)
                monitor.updateToggleButton(s.gamepadToggleButton)
                monitor.updateSendButton(s.gamepadSendButton)
            } else {
                startGamepadMonitor()
            }
        } else {
            gamepadMonitor = nil
        }
        settingsWindowController?.updateGamepadMonitor(gamepadMonitor)

        print("Settings updated: toggle=\(s.toggleModifier.displayName), hold=\(s.holdModifier.displayName), gamepad=\(s.gamepadEnabled ? "on" : "off")")
    }
}
