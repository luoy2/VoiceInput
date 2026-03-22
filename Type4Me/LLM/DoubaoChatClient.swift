import Foundation
import os

actor DoubaoChatClient: LLMClient {

    private let logger = Logger(subsystem: "com.type4me.llm", category: "DoubaoChatClient")

    /// Pre-establish TCP+TLS connection so the first real request skips handshake.
    func warmUp(baseURL: String) async {
        guard let url = URL(string: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: request)
        logger.info("LLM connection pre-warmed to \(baseURL)")
    }

    /// Process text through Doubao ARK API (OpenAI-compatible streaming).
    /// Returns the full LLM response as a single string.
    func process(text: String, prompt: String, config: LLMConfig) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return text }
        let finalPrompt = prompt.replacingOccurrences(of: "{text}", with: trimmedText)

        guard let url = URL(string: "\(config.baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ChatRequest(
            model: config.model,
            messages: [ChatMessage(role: "user", content: finalPrompt)],
            stream: true,
            thinking: ThinkingConfig(type: "disabled")
        )
        request.httpBody = try JSONEncoder().encode(body)

        logger.info("LLM request: \(text.count) chars, endpoint=\(config.model)")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.requestFailed(0)
        }
        guard http.statusCode == 200 else {
            logger.error("LLM HTTP \(http.statusCode)")
            throw LLMError.requestFailed(http.statusCode)
        }

        // Parse SSE stream
        var result = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
                  let content = chunk.choices.first?.delta.content
            else { continue }
            result += content
        }

        logger.info("LLM result: \(result.count) chars")
        return result
    }
}

// MARK: - Request/Response Types

struct ThinkingConfig: Encodable, Sendable {
    let type: String
}

struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let thinking: ThinkingConfig?
}

struct ChatMessage: Codable, Sendable, Equatable {
    let role: String
    let content: String
}

struct ChatStreamChunk: Decodable, Sendable {
    let choices: [ChunkChoice]
}

struct ChunkChoice: Decodable, Sendable {
    let delta: ChunkDelta
}

struct ChunkDelta: Decodable, Sendable {
    let content: String?
}

enum LLMError: Error {
    case invalidURL
    case requestFailed(Int)
}
