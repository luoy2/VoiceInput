import Foundation

struct ClaudeLLMConfig: LLMProviderConfig, Sendable {

    static let provider = LLMProvider.claude

    static var credentialFields: [CredentialField] {[
        CredentialField(
            key: "apiKey", label: "API Key",
            placeholder: "sk-ant-...",
            isSecure: true, isOptional: false, defaultValue: ""
        ),
        CredentialField(
            key: "model", label: L("模型", "Model"),
            placeholder: "claude-sonnet-4-5-20250514",
            isSecure: false, isOptional: false, defaultValue: ""
        ),
        CredentialField(
            key: "baseURL", label: "Base URL",
            placeholder: "https://api.anthropic.com/v1",
            isSecure: false, isOptional: true, defaultValue: "https://api.anthropic.com/v1"
        ),
    ]}

    let apiKey: String
    let model: String
    let baseURL: String
    let maxTokens: Int

    init?(credentials: [String: String]) {
        guard let key = credentials["apiKey"], !key.isEmpty,
              let model = credentials["model"], !model.isEmpty
        else { return nil }
        self.apiKey = key
        self.model = model
        self.baseURL = credentials["baseURL"]?.isEmpty == false
            ? credentials["baseURL"]!
            : LLMProvider.claude.defaultBaseURL
        self.maxTokens = Int(credentials["maxTokens"] ?? "") ?? 4096
    }

    func toCredentials() -> [String: String] {
        ["apiKey": apiKey, "model": model, "baseURL": baseURL]
    }

    func toLLMConfig() -> LLMConfig {
        LLMConfig(apiKey: apiKey, model: model, baseURL: baseURL)
    }
}
