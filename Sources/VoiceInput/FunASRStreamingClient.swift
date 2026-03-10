import AVFoundation
import Foundation

class FunASRStreamingClient {

    private var webSocketTask: URLSessionWebSocketTask?
    private let endpoint: String
    private let mode: String  // "2pass", "online", "offline"

    // Callbacks
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((Result<String, Error>) -> Void)?

    // Chunk accumulation: 600ms at 16kHz 16-bit mono = 9600 samples * 2 bytes
    private var pcmBuffer = Data()
    private let chunkSize = 19200

    // State
    private var isConnected = false
    private var receivedFinalResult = false

    init(endpoint: String, mode: String) {
        self.endpoint = endpoint
        self.mode = mode
    }

    // MARK: - Lifecycle

    func connect() {
        guard let url = URL(string: endpoint) else {
            onFinalResult?(.failure(makeError("Invalid WebSocket URL: \(endpoint)")))
            return
        }

        let task = URLSession.shared.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        let config: [String: Any] = [
            "mode": mode,
            "wav_name": "voiceinput",
            "is_speaking": true,
            "wav_format": "pcm",
            "audio_fs": 16000,
            "chunk_size": [5, 10, 5]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            onFinalResult?(.failure(makeError("Failed to build config JSON")))
            return
        }

        task.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                self?.handleError(error)
                return
            }
            self?.isConnected = true
            self?.startReceiving()
        }
    }

    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected else { return }

        // Convert Float32 to Int16 PCM
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[i]))
            var int16Sample = Int16(sample * Float(Int16.max))
            withUnsafeBytes(of: &int16Sample) { pcmBuffer.append(contentsOf: $0) }
        }

        // Send complete chunks
        while pcmBuffer.count >= chunkSize {
            let chunk = Data(pcmBuffer.prefix(chunkSize))
            pcmBuffer = Data(pcmBuffer.dropFirst(chunkSize))
            webSocketTask?.send(.data(chunk)) { [weak self] error in
                if let error = error {
                    self?.handleError(error)
                }
            }
        }
    }

    func finishSpeaking() {
        // Send remaining PCM data
        if !pcmBuffer.isEmpty {
            let remaining = pcmBuffer
            pcmBuffer = Data()
            webSocketTask?.send(.data(remaining)) { _ in }
        }

        // Send end signal
        let endSignal = "{\"is_speaking\": false}"
        webSocketTask?.send(.string(endSignal)) { [weak self] error in
            if let error = error {
                self?.handleError(error)
            }
        }

        // Timeout: if no final result in 15s, report error
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.receivedFinalResult else { return }
            self.handleError(self.makeError("Timeout waiting for final result"))
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // MARK: - Receiving

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                if !self.receivedFinalResult {
                    self.startReceiving()
                }
            case .failure(let error):
                if !self.receivedFinalResult {
                    self.handleError(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let responseMode = json["mode"] as? String ?? ""
        let resultText = json["text"] as? String ?? ""
        let isFinal = json["is_final"] as? Bool ?? false
        let cleanedText = Self.cleanSenseVoice(resultText)

        DispatchQueue.main.async { [weak self] in
            if responseMode == "offline" || isFinal {
                self?.receivedFinalResult = true
                self?.onFinalResult?(.success(cleanedText))
                self?.disconnect()
            } else {
                if !cleanedText.isEmpty {
                    self?.onPartialResult?(cleanedText)
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.receivedFinalResult else { return }
            self.receivedFinalResult = true
            self.onFinalResult?(.failure(error))
            self.disconnect()
        }
    }

    /// Strip SenseVoice metadata tags like <|en|>, <|EMO_UNKNOWN|>, <|Speech|>
    private static func cleanSenseVoice(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeError(_ message: String) -> Error {
        NSError(domain: "FunASR", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
