import Foundation
import os

enum OpenAIASRError: Error, LocalizedError {
    case unsupportedProvider
    case invalidEndpoint(String)
    case noAudioData
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "OpenAIASRClient requires OpenAIASRConfig"
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

actor OpenAIASRClient: SpeechRecognizer {

    private let logger = Logger(
        subsystem: "com.type4me.asr",
        category: "OpenAIASRClient"
    )

    private var config: OpenAIASRConfig?
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
        guard let openAIConfig = config as? OpenAIASRConfig else {
            throw OpenAIASRError.unsupportedProvider
        }

        guard URL(string: openAIConfig.endpoint) != nil else {
            throw OpenAIASRError.invalidEndpoint(openAIConfig.endpoint)
        }

        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        eventContinuation = continuation
        _events = stream
        self.config = openAIConfig
        audioBuffer = Data()

        logger.info("OpenAI ASR client ready: \(openAIConfig.endpoint, privacy: .private(mask: .hash))")
        emitEvent(.ready)
    }

    func sendAudio(_ data: Data) async throws {
        audioBuffer.append(data)
    }

    func endAudio() async throws {
        guard let config else {
            emitEvent(.error(OpenAIASRError.unsupportedProvider))
            emitEvent(.completed)
            return
        }

        guard !audioBuffer.isEmpty else {
            emitEvent(.error(OpenAIASRError.noAudioData))
            emitEvent(.completed)
            return
        }

        let pcmData = audioBuffer
        audioBuffer = Data()

        logger.info("Transcribing \(pcmData.count) bytes of PCM audio")

        do {
            let wavData = Self.buildWAV(from: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
            let text = try await transcribe(wavData: wavData, config: config)
            let cleaned = Self.cleanSenseVoiceTags(text)

            logger.info("Transcription result: \(cleaned.prefix(80), privacy: .private)")

            let transcript = RecognitionTranscript(
                confirmedSegments: [cleaned],
                partialText: "",
                authoritativeText: cleaned,
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
        logger.info("OpenAI ASR client disconnected")
    }

    // MARK: - HTTP Transcription

    private func transcribe(wavData: Data, config: OpenAIASRConfig) async throws -> String {
        guard let url = URL(string: config.endpoint) else {
            throw OpenAIASRError.invalidEndpoint(config.endpoint)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30

        var body = Data()
        // file field
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.appendUTF8("\r\n")
        // model field
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8(config.model)
        body.appendUTF8("\r\n")
        // close boundary
        body.appendUTF8("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIASRError.httpError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw OpenAIASRError.invalidResponse(raw)
        }

        return text
    }

    // MARK: - WAV Builder

    /// Build a WAV file from raw PCM data (little-endian).
    private static func buildWAV(from pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize  // total file size minus 8 bytes for RIFF header

        var wav = Data()
        wav.reserveCapacity(44 + pcmData.count)

        // RIFF header
        wav.appendUTF8("RIFF")
        wav.appendLittleEndian(fileSize)
        wav.appendUTF8("WAVE")

        // fmt sub-chunk
        wav.appendUTF8("fmt ")
        wav.appendLittleEndian(UInt32(16))         // sub-chunk size
        wav.appendLittleEndian(UInt16(1))          // PCM format
        wav.appendLittleEndian(channels)
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(blockAlign)
        wav.appendLittleEndian(bitsPerSample)

        // data sub-chunk
        wav.appendUTF8("data")
        wav.appendLittleEndian(dataSize)
        wav.append(pcmData)

        return wav
    }

    // MARK: - SenseVoice Tag Cleanup

    /// Strip SenseVoice metadata tags like <|en|>, <|EMO_UNKNOWN|>, <|Speech|>, <|withitn|>
    private static func cleanSenseVoiceTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func emitEvent(_ event: RecognitionEvent) {
        eventContinuation?.yield(event)
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(string.data(using: .utf8)!)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 4))
    }
}
