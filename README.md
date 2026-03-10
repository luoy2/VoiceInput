# VoiceInput

A lightweight macOS menu bar app that converts speech to text. Press a hotkey to record, release to transcribe, and the text is automatically pasted into your active application.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-orange) ![Swift](https://img.shields.io/badge/Swift-5.9-FA7343)

## Features

- **Hotkey-triggered recording** — Tap a modifier key (Ctrl/Option/Shift/Cmd/Fn) to start/stop recording
- **Auto-paste** — Transcribed text is automatically pasted via Cmd+V into the frontmost app
- **Multiple ASR providers** — Local (OpenAI-compatible), Groq, Gemini, FunASR Streaming
- **Gamepad support** — Use a Bluetooth gamepad button (e.g. 8BitDo Zero 2) as trigger
- **Visual feedback** — Floating overlay with waveform animation during recording
- **Audio feedback** — Sound effects on recording start/stop
- **Configurable** — Choose input device, hotkey, ASR provider, endpoint, and model

## Install

### Download DMG (recommended)

Download the latest `.dmg` from [Releases](../../releases), drag `VoiceInput.app` to Applications.

> **First launch:** Right-click → Open to bypass Gatekeeper (the app is ad-hoc signed, not notarized).

### Build from source

Requires **macOS 13+** and **Apple Silicon** (M1/M2/M3/M4). Intel Macs are not supported.

```bash
swift build -c release

# Package into .app manually:
mkdir -p VoiceInput.app/Contents/{MacOS,Resources}
cp .build/release/VoiceInput VoiceInput.app/Contents/MacOS/
cp Info.plist VoiceInput.app/Contents/
cp AppIcon.icns VoiceInput.app/Contents/Resources/
cp Sources/VoiceInput/Resources/*.wav VoiceInput.app/Contents/Resources/
codesign --force --deep --sign - VoiceInput.app
```

## Permissions

On first launch, you'll be prompted to grant:

- **Microphone** — Required for audio recording
- **Accessibility** — Required for global hotkey detection and Cmd+V paste simulation

## ASR Provider Setup

Open the app's **Settings** (click the menu bar icon → Settings) to configure your ASR provider.

### Local (OpenAI-compatible)

For self-hosted models like [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) or [Whisper](https://github.com/openai/whisper) exposed via an OpenAI-compatible API (e.g. [faster-whisper-server](https://github.com/fedirz/faster-whisper-server)).

| Setting | Value |
|---------|-------|
| Endpoint | `http://localhost:10301/v1/audio/transcriptions` (adjust host/port) |
| Model | `sensevoice` (or your model name) |
| API Key | Not required for most local setups |

### Groq

Uses Groq's hosted Whisper API. Very fast, free tier available.

1. Get an API key at [console.groq.com/keys](https://console.groq.com/keys)
2. Configure in Settings:

| Setting | Value |
|---------|-------|
| Endpoint | `https://api.groq.com/openai/v1/audio/transcriptions` (pre-filled) |
| Model | `whisper-large-v3-turbo` (pre-filled) |
| API Key | Your Groq API key |

### Gemini

Uses Google's Gemini multimodal API for transcription.

1. Get an API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Configure in Settings:

| Setting | Value |
|---------|-------|
| Endpoint | `https://generativelanguage.googleapis.com/v1beta` (pre-filled) |
| Model | `gemini-3.1-flash-lite-preview` (pre-filled) |
| API Key | Your Google AI API key |

### FunASR Streaming

WebSocket-based streaming ASR using [FunASR](https://github.com/modelscope/FunASR). Shows partial results in real-time during recording.

Deploy the FunASR server, then configure:

| Setting | Value |
|---------|-------|
| Endpoint | `ws://localhost:10096` (adjust host/port) |
| Model | `2pass` / `online` / `offline` |

## License

MIT
