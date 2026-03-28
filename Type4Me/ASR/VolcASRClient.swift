import Foundation
import os

enum VolcASRError: Error, LocalizedError {
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider: return "VolcASRClient requires VolcanoASRConfig"
        }
    }
}

actor VolcASRClient: SpeechRecognizer {

    private static let endpoint =
        URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!

    private let logger = Logger(
        subsystem: "com.type4me.asr",
        category: "VolcASRClient"
    )

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private var eventContinuation: AsyncStream<RecognitionEvent>.Continuation?
    private var _events: AsyncStream<RecognitionEvent>?

    var events: AsyncStream<RecognitionEvent> {
        if let existing = _events {
            return existing
        }
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        self.eventContinuation = continuation
        self._events = stream
        return stream
    }

    // MARK: - Connect

    func connect(config: any ASRProviderConfig, options: ASRRequestOptions = ASRRequestOptions()) async throws {
        guard let volcConfig = config as? VolcanoASRConfig else {
            throw VolcASRError.unsupportedProvider
        }

        // Ensure fresh event stream
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        self.eventContinuation = continuation
        self._events = stream

        let connectId = UUID().uuidString

        var request = URLRequest(url: Self.endpoint)
        request.setValue(volcConfig.accessKey, forHTTPHeaderField: "x-api-key")
        request.setValue("volc.seedasr.sauc.duration", forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        self.webSocketTask = task

        // Send full_client_request (no compression, plain JSON)
        let payload = VolcProtocol.buildClientRequest(
            uid: volcConfig.uid,
            options: options
        )

        let header = VolcHeader(
            messageType: .fullClientRequest,
            flags: .noSequence,
            serialization: .json,
            compression: .none
        )
        let message = VolcProtocol.encodeMessage(header: header, payload: payload)

        lastTranscript = .empty
        audioPacketCount = 0
        totalAudioBytes = 0
        NSLog("[ASR] Sending full_client_request (%d bytes)", message.count)
        try await task.send(.data(message))

        NSLog("[ASR] full_client_request sent OK")

        // Start receive loop
        startReceiveLoop()
    }

    // MARK: - Send Audio

    private var audioPacketCount = 0
    private var totalAudioBytes = 0
    private var lastTranscript: RecognitionTranscript = .empty

    func sendAudio(_ data: Data) async throws {
        guard let task = webSocketTask else { return }
        audioPacketCount += 1
        totalAudioBytes += data.count
        let packet = VolcProtocol.encodeAudioPacket(
            audioData: data,
            isLast: false
        )
        try await task.send(.data(packet))
    }

    // MARK: - End Audio

    func endAudio() async throws {
        guard let task = webSocketTask else { return }
        let packet = VolcProtocol.encodeAudioPacket(
            audioData: Data(),
            isLast: true
        )
        try await task.send(.data(packet))
        NSLog("[ASR] Sent last audio packet (empty, isLast=true)")
    }

    // MARK: - Disconnect

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        _events = nil
        NSLog("[ASR] Disconnected")
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let task = await self.webSocketTask else { break }
                    let message = try await task.receive()
                    await self.handleMessage(message)
                } catch {
                    NSLog("[ASR] Receive loop error: %@", String(describing: error))
                    if !Task.isCancelled {
                        if await self.audioPacketCount == 0 {
                            // No audio sent yet — real connection/auth error.
                            await self.emitEvent(.error(error))
                        } else {
                            // Audio was flowing — socket close is normal session end
                            // (especially through proxies that don't relay WS close frames).
                            NSLog("[ASR] Treating as normal session end (sent %d packets)", await self.audioPacketCount)
                        }
                        await self.emitEvent(.completed)
                    }
                    break
                }
            }
            NSLog("[ASR] Receive loop ended")
            // Finish the event stream so consumers (eventConsumptionTask) can complete.
            await self.eventContinuation?.finish()
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            let headerByte1 = data.count > 1 ? data[1] : 0
            let msgType = (headerByte1 >> 4) & 0x0F

            // Server error (0xF)
            if msgType == 0x0F {
                // Always try to decode and log the error
                // Log raw error data for debugging
                let hexDump = data.prefix(200).map { String(format: "%02x", $0) }.joined(separator: " ")
                DebugFileLogger.log("ASR server error raw (\(data.count) bytes): \(hexDump)")
                // Try to decompress if gzipped, then decode
                let errorPayload: Data
                if data.count > 8 {
                    let headerSize = Int(data[0] & 0x0F) * 4
                    let compress = Int(data[2]) & 0x0F
                    var offset = headerSize
                    let flags = Int(data[1]) & 0x0F
                    if flags == 1 || flags == 3 { offset += 4 }
                    if data.count > offset + 4 {
                        let pSize = Int(UInt32(bigEndian: data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self) }))
                        let pData = data[(offset+4)..<min(offset+4+pSize, data.count)]
                        if compress == 1, let decompressed = try? VolcProtocol.gzipDecompress(Data(pData)) {
                            errorPayload = decompressed
                        } else {
                            errorPayload = Data(pData)
                        }
                        if let errorStr = String(data: errorPayload, encoding: .utf8) {
                            DebugFileLogger.log("ASR server error decoded: \(errorStr)")
                        }
                    }
                }
                do {
                    _ = try VolcProtocol.decodeServerResponse(data)
                } catch {
                    NSLog("[ASR] Server error parse (packets=%d): %@", audioPacketCount, String(describing: error))
                    DebugFileLogger.log("ASR server error (packets=\(audioPacketCount)): \(String(describing: error))")
                    emitEvent(.error(error))
                }
                emitEvent(.completed)
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                webSocketTask = nil
                return
            }

            do {
                let response = try VolcProtocol.decodeServerResponse(data)
                let transcript = makeTranscript(
                    from: response.result,
                    isFinal: response.header.flags == .asyncFinal
                )
                guard transcript != lastTranscript else { return }
                lastTranscript = transcript

                NSLog(
                    "[ASR] Transcript update confirmed=%d partial=%d final=%@",
                    transcript.confirmedSegments.count,
                    transcript.partialText.count,
                    transcript.isFinal ? "yes" : "no"
                )
                emitEvent(.transcript(transcript))

                if transcript.isFinal, !transcript.authoritativeText.isEmpty {
                    NSLog("[ASR] Final transcript: '%@'", transcript.authoritativeText)
                }
            } catch {
                NSLog("[ASR] Decode error: %@", String(describing: error))
                emitEvent(.error(error))
            }

        case .string(let text):
            NSLog("[ASR] Unexpected text message: %@", text)

        @unknown default:
            break
        }
    }

    private func emitEvent(_ event: RecognitionEvent) {
        eventContinuation?.yield(event)
    }

    private func makeTranscript(from result: VolcASRResult, isFinal: Bool) -> RecognitionTranscript {
        let confirmedSegments = result.utterances
            .filter(\.definite)
            .map(\.text)
            .filter { !$0.isEmpty }
        let partialText = result.utterances.last(where: { !$0.definite && !$0.text.isEmpty })?.text ?? ""
        let composedText = (confirmedSegments + (partialText.isEmpty ? [] : [partialText])).joined()
        let authoritativeText = result.text.isEmpty ? composedText : result.text
        return RecognitionTranscript(
            confirmedSegments: confirmedSegments,
            partialText: partialText,
            authoritativeText: authoritativeText,
            isFinal: isFinal
        )
    }
}
