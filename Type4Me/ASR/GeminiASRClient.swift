import Foundation
import os

enum GeminiASRError: Error, LocalizedError {
    case unsupportedProvider
    case invalidEndpoint(String)
    case noAudioData
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "GeminiASRClient requires GoogleASRConfig"
        case .invalidEndpoint(let url):
            return "Invalid endpoint URL: \(url)"
        case .noAudioData:
            return "No audio data was recorded"
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        case .invalidResponse(let raw):
            return "Unexpected response: \(raw)"
        }
    }
}

actor GeminiASRClient: SpeechRecognizer {

    private let logger = Logger(
        subsystem: "com.type4me.asr",
        category: "GeminiASRClient"
    )

    private static let transcriptionPrompt =
        "Transcribe this audio exactly. Output ONLY the spoken words, nothing else. " +
        "Do NOT include timestamps, speaker labels, time codes, or any formatting. " +
        "Preserve the original language."

    private var config: GoogleASRConfig?
    private var audioBuffer = Data()
    private var eventContinuation: AsyncStream<RecognitionEvent>.Continuation?
    private var _events: AsyncStream<RecognitionEvent>?

    var events: AsyncStream<RecognitionEvent> {
        if let existing = _events {
            return existing
        }
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        eventContinuation = continuation
        _events = stream
        return stream
    }

    func connect(config: any ASRProviderConfig, options: ASRRequestOptions) async throws {
        guard let geminiConfig = config as? GoogleASRConfig else {
            throw GeminiASRError.unsupportedProvider
        }

        let urlString = "\(geminiConfig.baseURL)/models/\(geminiConfig.model):generateContent?key=\(geminiConfig.apiKey)"
        guard URL(string: urlString) != nil else {
            throw GeminiASRError.invalidEndpoint(urlString)
        }

        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        eventContinuation = continuation
        _events = stream
        self.config = geminiConfig
        audioBuffer = Data()

        logger.info("Gemini ASR client ready: \(geminiConfig.baseURL, privacy: .private(mask: .hash))")
        emitEvent(.ready)
    }

    func sendAudio(_ data: Data) async throws {
        audioBuffer.append(data)
    }

    func endAudio() async throws {
        guard let config else {
            emitEvent(.error(GeminiASRError.unsupportedProvider))
            emitEvent(.completed)
            return
        }

        guard !audioBuffer.isEmpty else {
            emitEvent(.error(GeminiASRError.noAudioData))
            emitEvent(.completed)
            return
        }

        let pcmData = audioBuffer
        audioBuffer = Data()

        logger.info("Transcribing \(pcmData.count) bytes of PCM audio via Gemini")

        do {
            let wavData = Self.buildWAV(from: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
            let text = try await transcribe(wavData: wavData, config: config)

            logger.info("Transcription result: \(text.prefix(80), privacy: .private)")

            let transcript = RecognitionTranscript(
                confirmedSegments: [text],
                partialText: "",
                authoritativeText: text,
                isFinal: true
            )
            emitEvent(.transcript(transcript))
            emitEvent(.completed)
        } catch {
            logger.error("Transcription failed: \(String(describing: error), privacy: .public)")
            emitEvent(.error(error))
            emitEvent(.completed)
        }
    }

    func disconnect() {
        config = nil
        audioBuffer = Data()
        eventContinuation?.finish()
        eventContinuation = nil
        _events = nil
        logger.info("Gemini ASR client disconnected")
    }

    // MARK: - Gemini generateContent API

    private func transcribe(wavData: Data, config: GoogleASRConfig) async throws -> String {
        let urlString = "\(config.baseURL)/models/\(config.model):generateContent?key=\(config.apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiASRError.invalidEndpoint(urlString)
        }

        let audioBase64 = wavData.base64EncodedString()

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": "audio/wav",
                            "data": audioBase64
                        ]
                    ],
                    [
                        "text": Self.transcriptionPrompt
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiASRError.httpError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw GeminiASRError.invalidResponse(raw)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WAV Builder

    private static func buildWAV(from pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var wav = Data()
        wav.reserveCapacity(44 + pcmData.count)

        // RIFF header
        wav.appendGeminiUTF8("RIFF")
        wav.appendGeminiLE(fileSize)
        wav.appendGeminiUTF8("WAVE")

        // fmt sub-chunk
        wav.appendGeminiUTF8("fmt ")
        wav.appendGeminiLE(UInt32(16))
        wav.appendGeminiLE(UInt16(1))       // PCM format
        wav.appendGeminiLE(channels)
        wav.appendGeminiLE(sampleRate)
        wav.appendGeminiLE(byteRate)
        wav.appendGeminiLE(blockAlign)
        wav.appendGeminiLE(bitsPerSample)

        // data sub-chunk
        wav.appendGeminiUTF8("data")
        wav.appendGeminiLE(dataSize)
        wav.append(pcmData)

        return wav
    }

    private func emitEvent(_ event: RecognitionEvent) {
        eventContinuation?.yield(event)
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func appendGeminiUTF8(_ string: String) {
        append(string.data(using: .utf8)!)
    }

    mutating func appendGeminiLE(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    mutating func appendGeminiLE(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 4))
    }
}
