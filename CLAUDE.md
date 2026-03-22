# Type4Me — Development Guide

## Overview

macOS menu bar voice input tool with multi-provider ASR support (Volcengine implemented, others coming soon) and optional LLM post-processing.
Swift Package Manager project, no Xcode project file, no third-party dependencies.

## Build & Run

```bash
swift build -c release
```

The built binary is at `.build/release/Type4Me`. To package it as a `.app` bundle, see `scripts/deploy.sh`.

## ASR Provider Architecture

Multi-provider ASR support via `ASRProvider` enum + `ASRProviderConfig` protocol + `ASRProviderRegistry`.

- `ASRProvider` enum: 12 cases (openai/azure/google/aws/deepgram/assemblyai/volcano/aliyun/tencent/baidu/iflytek/custom)
- Each provider has its own Config type (e.g., `VolcanoASRConfig`) defining `credentialFields` for dynamic UI rendering
- `ASRProviderRegistry`: maps provider to config type + client factory; `isAvailable` indicates whether a client implementation exists
- Currently only `volcano` has a non-nil `createClient`; others are coming soon

### Adding a New Provider

1. Create a Config file in `Type4Me/ASR/Providers/`, implementing `ASRProviderConfig`
2. Write the client (implementing `SpeechRecognizer` protocol)
3. Register `createClient` in `ASRProviderRegistry.all`

## Credential Storage

Credentials are stored at `~/Library/Application Support/Type4Me/credentials.json` (file permissions 0600).

**Do not rely on environment variables** for credentials in production. GUI-launched apps cannot read shell env vars from `~/.zshrc`. Credentials must be configured through the Settings UI.

### credentials.json Structure

```json
{
    "tf_asr_volcano": { "appKey": "...", "accessKey": "...", "resourceId": "..." },
    "tf_asr_openai": { "apiKey": "sk-..." },
    "tf_llmApiKey": "...",
    "tf_llmModel": "...",
    "tf_llmBaseURL": "..."
}
```

## Permissions Required

| Permission | Purpose |
|---|---|
| Microphone | Audio capture |
| Accessibility | Global hotkey listening + text injection into other apps |

## Key Files

| Path | Responsibility |
|---|---|
| `Type4Me/ASR/ASRProvider.swift` | Provider enum + protocol + CredentialField |
| `Type4Me/ASR/ASRProviderRegistry.swift` | Registry: provider → config + client factory |
| `Type4Me/ASR/Providers/*.swift` | Per-vendor Config implementations |
| `Type4Me/ASR/SpeechRecognizer.swift` | SpeechRecognizer protocol + LLMConfig + event types |
| `Type4Me/ASR/VolcASRClient.swift` | Streaming ASR (WebSocket) |
| `Type4Me/ASR/VolcFlashASRClient.swift` | Flash ASR (HTTP, one-shot) |
| `Type4Me/Session/RecognitionSession.swift` | Core state machine: record → ASR → inject |
| `Type4Me/Audio/AudioCaptureEngine.swift` | Audio capture, `getRecordedAudio()` returns full recording |
| `Type4Me/UI/AppState.swift` | `ProcessingMode` definition, built-in mode list |
| `Type4Me/Services/KeychainService.swift` | Credential read/write (provider groups + migration) |
| `Type4Me/Services/HotwordStorage.swift` | ASR hotword storage (UserDefaults) |
| `scripts/deploy.sh` | Build + deploy + launch |
