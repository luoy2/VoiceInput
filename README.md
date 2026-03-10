# VoiceInput

> **This README is written for AI agents.** If you're an agent helping a user set up VoiceInput, follow the instructions below.

A macOS menu bar app that converts speech to text. Hold a button (keyboard modifier or Bluetooth gamepad) to record, release to transcribe, text is auto-pasted into the active application.

**Requirements:** macOS 13+, Apple Silicon (M1/M2/M3/M4) only. Intel Macs are not supported.

## Quick Start (for end users)

Download `VoiceInput.dmg` from [Releases](../../releases). Drag to Applications. Right-click → Open on first launch (ad-hoc signed, not notarized). Grant Microphone and Accessibility permissions when prompted.

## Build from Source

```bash
swift build -c release

mkdir -p VoiceInput.app/Contents/{MacOS,Resources}
cp .build/release/VoiceInput VoiceInput.app/Contents/MacOS/
cp Info.plist VoiceInput.app/Contents/
cp AppIcon.icns VoiceInput.app/Contents/Resources/
cp Sources/VoiceInput/Resources/*.wav VoiceInput.app/Contents/Resources/
codesign --force --deep --sign - VoiceInput.app

open VoiceInput.app
```

## ASR Provider Configuration

The app stores all settings in `UserDefaults`. Configure via the Settings UI (menu bar icon → Settings). Four providers are supported:

### 1. Groq (recommended — fast, free tier)

Hosted Whisper API. Lowest latency for cloud providers.

```
Provider: Groq
Endpoint: https://api.groq.com/openai/v1/audio/transcriptions
Model:    whisper-large-v3-turbo
API Key:  <get from https://console.groq.com/keys>
```

### 2. Gemini

Google's multimodal API. Good for multilingual transcription.

```
Provider: Gemini
Endpoint: https://generativelanguage.googleapis.com/v1beta
Model:    gemini-3.1-flash-lite-preview
API Key:  <get from https://aistudio.google.com/apikey>
```

### 3. Local (OpenAI-compatible)

Self-hosted ASR server exposing the OpenAI `/v1/audio/transcriptions` endpoint. Works with:
- [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) — best for Chinese + English mixed
- [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) — Whisper with CTranslate2
- Any OpenAI-compatible audio transcription API

```
Provider: Local
Endpoint: http://<host>:<port>/v1/audio/transcriptions
Model:    <model name served by your backend>
API Key:  <optional, depends on your server>
```

### 4. FunASR Streaming

WebSocket-based streaming ASR using [FunASR](https://github.com/modelscope/FunASR). Unique feature: shows partial transcription results in real-time while recording.

Deploy server:
```bash
docker run -p 10096:10095 registry.cn-hangzhou.aliyuncs.com/funasr_repo/funasr:funasr-runtime-sdk-online-cpu-0.1.12 bash run_server.sh --model-dir damo/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-online --vad-dir damo/speech_fsmn_vad_zh-cn-16k-common-onnx --punc-dir damo/punc_ct-transformer_cn-en-common-vocab471067-large-onnx
```

```
Provider: FunASR
Endpoint: ws://<host>:10096
Model:    2pass (recommended) / online / offline
```

## System Permissions

| Permission | Why | How |
|-----------|-----|-----|
| Microphone | Audio recording | Auto-prompted via `AVCaptureDevice` on first use |
| Accessibility | Global hotkey + Cmd+V paste simulation | Auto-prompted via `AXIsProcessTrustedWithOptions`; if denied, go to System Settings → Privacy & Security → Accessibility → enable VoiceInput |

## Trigger Methods

- **Keyboard modifier key:** Tap and release a modifier key (Ctrl/Option/Shift/Cmd/Fn) within 350ms to toggle recording. Configurable in Settings.
- **Bluetooth gamepad:** Hold a button to record, release to stop. Uses IOKit HID (works even when app is not frontmost). Tested with 8BitDo Zero 2.

## License

MIT
