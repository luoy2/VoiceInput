import AppKit
import WebKit

private class NonActivatingPanel: NSPanel {
    var allowKey = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

class OverlayWindow: NSObject, WKScriptMessageHandler {
    private let window: NonActivatingPanel
    private let webView: WKWebView
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    private var htmlLoaded = false
    private var hideWorkItem: DispatchWorkItem?
    private var autoHideWorkItem: DispatchWorkItem?

    override init() {
        let width: CGFloat = 420
        let height: CGFloat = 140

        window = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver  // Above everything
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false

        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        super.init()

        config.userContentController.add(self, name: "action")
        window.contentView = webView

        // Position bottom-center
        if let screen = NSScreen.main {
            let x = screen.frame.midX - width / 2
            let y = screen.frame.minY + 60
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.onEscape = { [weak self] in
            self?.onCancel?()
        }

        // Load HTML immediately
        webView.loadHTMLString(Self.html, baseURL: nil)
        htmlLoaded = true
    }

    func showRecording() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        window.allowKey = true
        window.orderFrontRegardless()
        window.makeKey()
        eval("startRecording()")
    }

    func releaseKey() {
        window.allowKey = false
        window.resignKey()
    }

    func updatePartialTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        eval("updatePartialText('\(escaped)')")
    }

    func showProcessing() {
        eval("showProcessing()")
    }

    func showSuccess(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        eval("showSuccess('\(escaped)')")
        SoundFeedback.playDone()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        autoHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    func showError(_ message: String) {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        eval("showError('\(escaped)')")
        SoundFeedback.playError()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        autoHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    func updateLevels(_ levels: [Float]) {
        let json = "[" + levels.map { String(format: "%.3f", $0) }.joined(separator: ",") + "]"
        eval("updateLevels(\(json))")
    }

    func hide() {
        releaseKey()
        eval("hideOverlay()")
        let item = DispatchWorkItem { [weak self] in
            self?.window.orderOut(nil)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        switch body {
        case "cancel": onCancel?()
        case "done": onDone?()
        default: break
        }
    }

    private func eval(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Embedded HTML

    private static let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        background: transparent;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
        -webkit-font-smoothing: antialiased;
        user-select: none;
        overflow: hidden;
      }
      #container {
        display: flex; flex-direction: column; align-items: center;
        opacity: 0; transform: translateY(-8px) scale(0.96);
        transition: opacity 0.25s ease, transform 0.25s ease;
      }
      #container.visible { opacity: 1; transform: translateY(0) scale(1); }

      #pill {
        display: flex; align-items: center; gap: 0;
        background: rgba(30, 30, 30, 0.92);
        backdrop-filter: blur(40px) saturate(180%);
        -webkit-backdrop-filter: blur(40px) saturate(180%);
        border-radius: 28px; padding: 6px;
        border: 0.5px solid rgba(255,255,255,0.08);
        box-shadow: 0 8px 32px rgba(0,0,0,0.4), 0 2px 8px rgba(0,0,0,0.2),
                    inset 0 0.5px 0 rgba(255,255,255,0.05);
        height: 44px; min-width: 200px;
        transition: all 0.3s cubic-bezier(0.4,0,0.2,1);
      }

      .btn {
        width: 32px; height: 32px; border-radius: 50%; border: none;
        display: flex; align-items: center; justify-content: center;
        cursor: pointer; transition: all 0.15s ease; flex-shrink: 0;
        background: rgba(255,255,255,0.12);
      }
      .btn:hover { transform: scale(1.08); background: rgba(255,255,255,0.18); }
      .btn:active { transform: scale(0.95); }
      .btn svg { width: 14px; height: 14px; }

      #waveform-area {
        flex: 1; display: flex; align-items: center; justify-content: center;
        height: 32px; padding: 0 12px; min-width: 120px;
      }
      #waveform { display: flex; align-items: center; justify-content: center; gap: 2.5px; height: 28px; }
      .bar { width: 3px; border-radius: 1.5px; background: #fff; height: 4px; transition: height 0.08s ease; opacity: 0.9; }

      #processing { display: none; align-items: center; gap: 8px; padding: 0 12px; color: rgba(255,255,255,0.7); font-size: 13px; font-weight: 500; }
      .spinner { width: 16px; height: 16px; border: 2px solid rgba(255,255,255,0.15); border-top-color: rgba(255,255,255,0.8); border-radius: 50%; animation: spin 0.7s linear infinite; }
      @keyframes spin { to { transform: rotate(360deg); } }

      #status-text { display: none; padding: 0 12px; color: rgba(255,255,255,0.85); font-size: 13px; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 300px; }

      #transcript {
        margin-top: 8px; background: rgba(30,30,30,0.88);
        backdrop-filter: blur(40px) saturate(180%);
        border-radius: 12px; padding: 10px 16px;
        border: 0.5px solid rgba(255,255,255,0.06);
        box-shadow: 0 4px 16px rgba(0,0,0,0.3);
        max-width: 400px; min-width: 200px;
        opacity: 0; transform: translateY(-4px);
        transition: opacity 0.2s ease, transform 0.2s ease;
        display: none;
      }
      #transcript.visible { opacity: 1; transform: translateY(0); display: block; }
      #transcript-text { color: rgba(255,255,255,0.9); font-size: 14px; line-height: 1.5; }

      .state-error #status-text { color: #FF6B6B; }
      .state-recording #pill {
        box-shadow: 0 8px 32px rgba(0,0,0,0.4), 0 2px 8px rgba(0,0,0,0.2),
                    0 0 20px rgba(255,59,48,0.08), inset 0 0.5px 0 rgba(255,255,255,0.05);
      }
    </style>
    </head>
    <body>
    <div id="container">
      <div id="pill">
        <button class="btn" id="btn-cancel" onclick="onCancel()">
          <svg viewBox="0 0 14 14" fill="none"><path d="M3 3L11 11M11 3L3 11" stroke="white" stroke-width="1.8" stroke-linecap="round"/></svg>
        </button>
        <div id="waveform-area"><div id="waveform"></div></div>
        <div id="processing"><div class="spinner"></div><span>Transcribing</span></div>
        <div id="status-text"></div>
        <button class="btn" id="btn-done" onclick="onDone()">
          <svg viewBox="0 0 16 16" fill="none"><path d="M3.5 8.5L6.5 11.5L12.5 4.5" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
        </button>
      </div>
      <div id="transcript"><div id="transcript-text"></div></div>
    </div>
    <script>
      const NUM_BARS = 24;
      const waveformEl = document.getElementById('waveform');
      const container = document.getElementById('container');
      const waveformArea = document.getElementById('waveform-area');
      const processing = document.getElementById('processing');
      const statusText = document.getElementById('status-text');
      const transcript = document.getElementById('transcript');
      const transcriptText = document.getElementById('transcript-text');
      const btnCancel = document.getElementById('btn-cancel');
      const btnDone = document.getElementById('btn-done');
      for (let i = 0; i < NUM_BARS; i++) { const b = document.createElement('div'); b.className = 'bar'; waveformEl.appendChild(b); }
      const bars = document.querySelectorAll('.bar');
      let idleFrame;
      function idleWave() {
        const t = Date.now() / 1000;
        bars.forEach((bar, i) => { bar.style.height = (4 + 2 * Math.sin(t * 2 + i * 0.3)) + 'px'; bar.style.opacity = '0.4'; });
        idleFrame = requestAnimationFrame(idleWave);
      }
      function startRecording() {
        container.className = 'visible state-recording';
        btnCancel.style.display = 'flex'; btnDone.style.display = 'flex';
        waveformArea.style.display = 'flex'; processing.style.display = 'none'; statusText.style.display = 'none';
        transcript.className = ''; transcript.style.display = 'none';
        cancelAnimationFrame(idleFrame); idleWave();
      }
      function updateLevels(levels) {
        cancelAnimationFrame(idleFrame);
        if (!Array.isArray(levels)) return;
        bars.forEach((bar, i) => { const l = levels[i % levels.length] || 0; bar.style.height = (4 + l * 24) + 'px'; bar.style.opacity = (0.5 + l * 0.5).toString(); });
      }
      function updatePartialText(text) {
        if (text && text.length > 0) {
          transcriptText.textContent = text;
          transcript.style.display = 'block';
          requestAnimationFrame(() => { transcript.className = 'visible'; });
        }
      }
      function showProcessing() {
        container.className = 'visible state-processing';
        btnCancel.style.display = 'none'; btnDone.style.display = 'none';
        processing.style.display = 'none'; statusText.style.display = 'none';
        waveformArea.style.display = 'flex';
        cancelAnimationFrame(idleFrame); idleWave();
      }
      function showSuccess(text) {
        container.className = 'visible state-success';
        btnCancel.style.display = 'none'; btnDone.style.display = 'none';
        processing.style.display = 'none'; statusText.style.display = 'none';
        waveformArea.style.display = 'flex';
        cancelAnimationFrame(idleFrame); idleWave();
        if (text && text.length > 0) {
          transcriptText.textContent = text;
          transcript.style.display = 'block';
          requestAnimationFrame(() => { transcript.className = 'visible'; });
        }
      }
      function showError(message) {
        container.className = 'visible state-error';
        btnCancel.style.display = 'none'; btnDone.style.display = 'none';
        waveformArea.style.display = 'none'; processing.style.display = 'none';
        statusText.style.display = 'block'; statusText.textContent = message || 'Error';
      }
      function hideOverlay() { container.className = ''; transcript.className = ''; cancelAnimationFrame(idleFrame); }
      function onCancel() { if (window.webkit && window.webkit.messageHandlers.action) window.webkit.messageHandlers.action.postMessage('cancel'); }
      function onDone() { if (window.webkit && window.webkit.messageHandlers.action) window.webkit.messageHandlers.action.postMessage('done'); }
      document.addEventListener('keydown', function(e) { if (e.key === 'Escape') onCancel(); });
    </script>
    </body>
    </html>
    """
}
