import Foundation
import os

enum VolcFlashASRError: Error, LocalizedError {
    case missingCredentials
    case serverError(code: String, message: String)
    case invalidResponse
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Missing VOLC_APP_KEY or VOLC_ACCESS_KEY"
        case .serverError(let code, let message): return "Flash ASR error \(code): \(message)"
        case .invalidResponse: return "Invalid response from flash ASR"
        case .emptyAudio: return "No audio data to recognize"
        }
    }
}

/// One-shot file-based ASR using Volcengine's flash recognition API.
/// Sends the complete recorded audio as a WAV file and returns the full text.
enum VolcFlashASRClient {

    private static let endpoint = URL(
        string: "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash"
    )!

    static func recognize(
        pcmData: Data,
        config: VolcanoASRConfig
    ) async throws -> String {
        guard !pcmData.isEmpty else { throw VolcFlashASRError.emptyAudio }

        let wavData = wavFromPCM(pcmData)
        let base64Audio = wavData.base64EncodedString()

        let body: [String: Any] = [
            "user": ["uid": config.uid],
            "audio": ["data": base64Audio],
            "request": [
                "model_name": "bigmodel",
                "enable_punc": true,
            ],
        ]

        let resourceId =
            ProcessInfo.processInfo.environment["VOLC_FLASH_RESOURCE_ID"]
            ?? "volc.bigasr.auc_turbo"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(config.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NSLog("[FlashASR] Sending %d bytes WAV (%d bytes base64), resourceId=%@",
              wavData.count, base64Audio.count, resourceId)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VolcFlashASRError.invalidResponse
        }

        let statusCode = http.value(forHTTPHeaderField: "X-Api-Status-Code") ?? "\(http.statusCode)"
        let logId = http.value(forHTTPHeaderField: "X-Tt-Logid") ?? "?"
        NSLog("[FlashASR] Response status=%@, logId=%@", statusCode, logId)

        if statusCode != "20000000" {
            let message = http.value(forHTTPHeaderField: "X-Api-Message") ?? "Unknown"
            throw VolcFlashASRError.serverError(code: statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let text = result["text"] as? String
        else {
            if let raw = String(data: data.prefix(500), encoding: .utf8) {
                NSLog("[FlashASR] Unexpected response body: %@", raw)
            }
            throw VolcFlashASRError.invalidResponse
        }

        NSLog("[FlashASR] Recognized: %@", text)
        return text
    }

    // MARK: - WAV Encoding

    /// Wrap raw PCM Int16 mono 16kHz data in a WAV container.
    private static func wavFromPCM(_ pcmData: Data) -> Data {
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var wav = Data(capacity: 44 + pcmData.count)

        // RIFF header
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46])  // "RIFF"
        appendUInt32(&wav, fileSize)
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45])  // "WAVE"

        // fmt chunk
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])  // "fmt "
        appendUInt32(&wav, 16)       // chunk size
        appendUInt16(&wav, 1)        // PCM format
        appendUInt16(&wav, 1)        // channels
        appendUInt32(&wav, 16000)    // sample rate
        appendUInt32(&wav, 32000)    // byte rate (16000 * 1 * 16/8)
        appendUInt16(&wav, 2)        // block align (1 * 16/8)
        appendUInt16(&wav, 16)       // bits per sample

        // data chunk
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61])  // "data"
        appendUInt32(&wav, dataSize)
        wav.append(pcmData)

        return wav
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }
}
