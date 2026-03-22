import Foundation

/// Common interface for LLM clients (OpenAI-compatible and Claude).
protocol LLMClient: Sendable {
    func process(text: String, prompt: String, config: LLMConfig) async throws -> String
    func warmUp(baseURL: String) async
}
