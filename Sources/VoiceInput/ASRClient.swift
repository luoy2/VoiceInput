import Foundation

class ASRClient {
    private var endpointString: String
    private var modelName: String
    private var apiKey: String
    private var provider: ASRProvider

    init(endpoint: String, modelName: String, apiKey: String = "", provider: ASRProvider = .local) {
        self.endpointString = endpoint
        self.modelName = modelName
        self.apiKey = apiKey
        self.provider = provider
    }

    func updateConfiguration(endpoint: String, modelName: String, apiKey: String = "", provider: ASRProvider = .local) {
        self.endpointString = endpoint
        self.modelName = modelName
        self.apiKey = apiKey
        self.provider = provider
    }

    func transcribe(wavData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        switch provider {
        case .gemini:
            transcribeGemini(wavData: wavData, completion: completion)
        case .local, .groq:
            transcribeOpenAI(wavData: wavData, completion: completion)
        case .funasrStreaming:
            // Streaming is handled by FunASRStreamingClient, not this class
            completion(.failure(NSError(domain: "ASR", code: -4, userInfo: [NSLocalizedDescriptionKey: "Use streaming client for FunASR"])))
        }
    }

    // MARK: - OpenAI-compatible API (Local / Groq)

    private func transcribeOpenAI(wavData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let endpoint = URL(string: endpointString) else {
            completion(.failure(NSError(domain: "ASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid ASR endpoint URL"])))
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append(modelName)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    completion(.success(Self.cleanSenseVoice(text)))
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "Unknown response"
                    completion(.failure(NSError(domain: "ASR", code: -2, userInfo: [NSLocalizedDescriptionKey: raw])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Gemini API

    private func transcribeGemini(wavData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = "\(endpointString)/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "ASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini URL"])))
            return
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
                        "text": "Transcribe this audio exactly. Output ONLY the spoken words, nothing else. Do NOT include timestamps, speaker labels, time codes, or any formatting. Preserve the original language."
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "Unknown response"
                    completion(.failure(NSError(domain: "ASR", code: -2, userInfo: [NSLocalizedDescriptionKey: raw])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Strip SenseVoice metadata tags like <|en|>, <|EMO_UNKNOWN|>, <|Speech|>, <|withitn|>
    private static func cleanSenseVoice(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}
