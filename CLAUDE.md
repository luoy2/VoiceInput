# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a Swift Package Manager macOS app (not an Xcode project). It uses `swift-tools-version: 5.9` targeting macOS 13+.

```bash
# Build release and install to /Applications (includes code signing)
cd /Users/yluo/projects/VoiceInput && ./build.sh

# Build release + create DMG for distribution
./build.sh --dmg

# Build ad-hoc signed DMG (no Apple Developer ID needed, for sharing)
./dist.sh

# SPM build only (no .app bundle)
swift build -c release
```

There are no tests in this project. Build in Xcode via the `BuildProject` MCP tool or use `swift build` from CLI.

## Architecture

VoiceInput is a **menu bar-only macOS app** (`LSUIElement = true`) that records voice via a hotkey, sends audio to an ASR service, and pastes the transcribed text via simulated Cmd+V. It runs as an `NSApplication` with `setActivationPolicy(.accessory)`.

### Core Flow

1. **KeyMonitor** detects a modifier key tap (press and release < 350ms) globally via `NSEvent.addGlobalMonitorForEvents`
2. **AppDelegate.toggle()** starts/stops the recording cycle
3. **AudioRecorder** captures mic input via `AVAudioEngine`, resamples to 16kHz mono, accumulates PCM buffers, and builds a WAV file on stop
4. **ASRClient** sends the WAV to one of three providers (Local/Groq/Gemini) and returns transcribed text
5. **AppDelegate.paste()** copies text to clipboard and simulates Cmd+V via `CGEvent`
6. **OverlayWindow** shows a floating HUD (WKWebView with embedded HTML) at bottom-center of screen with waveform visualization during recording

### Key Files

- **`main.swift`** — App entry point; creates NSApplication + AppDelegate manually (no @main)
- **`SettingsWindow.swift`** — Contains `AppSettings` (UserDefaults-backed), `ModifierKeySpec`, `ASRProvider` enum, and the full Settings UI (AppKit, no SwiftUI)
- **`OverlayWindow.swift`** — Non-activating NSPanel with WKWebView; HTML/CSS/JS for the recording overlay is embedded as a static string
- **`AudioRecorder.swift`** — Also contains `AudioDevice` struct for enumerating CoreAudio input devices
- **`FunASRStreamingClient.swift`** — WebSocket client for FunASR streaming ASR (2pass/online/offline modes), sends 600ms PCM chunks
- **`GamepadMonitor.swift`** — Global gamepad input via IOKit `IOHIDManager` (not GCController, which doesn't work for menu bar apps). Hardcoded HID usage mappings for 8BitDo Zero 2.
- **`SoundFeedback.swift`** — Plays start/stop WAV sounds from `Resources/` on recording state changes

### ASR Providers (in `ASRClient.swift`)

- **Local**: OpenAI-compatible `/v1/audio/transcriptions` endpoint (multipart form upload). Strips SenseVoice metadata tags.
- **Groq**: Same OpenAI-compatible protocol, different endpoint/model. Requires API key.
- **Gemini**: Google `generateContent` API with base64 WAV in request body. Requires API key.
- **FunASR Streaming**: WebSocket-based streaming via `FunASRStreamingClient`, supports partial results during recording.

### System Permissions Required

- **Microphone** — For audio recording (prompted via `AVCaptureDevice`)
- **Accessibility** — For global hotkey monitoring and Cmd+V paste simulation (prompted via `AXIsProcessTrustedWithOptions`)

### Settings Persistence

All settings stored in `UserDefaults`: modifier key, ASR provider, endpoint, model, per-provider API keys, input device ID. The `AppSettings` struct handles load/save.

## Important Patterns

- The app uses **AppKit** throughout (no SwiftUI). UI is built programmatically.
- The overlay window is a `NonActivatingPanel` (subclass of `NSPanel`) so it doesn't steal focus from the frontmost app.
- Audio format: 16kHz, mono, Float32 PCM internally → 16-bit PCM WAV for API upload.
- Debug logging goes to `/tmp/voiceinput-debug.log`.
- Bundle ID: `com.yluo.voiceinput`
