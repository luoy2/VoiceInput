import Foundation

struct OpenAIASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.openai
    static let displayName = "OpenAI Whisper"
    static let defaultEndpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
    static let defaultModel = "whisper-large-v3-turbo"

    static let credentialFields: [CredentialField] = [
        CredentialField(key: "endpoint", label: "Endpoint URL", placeholder: defaultEndpoint, isSecure: false, isOptional: false, defaultValue: defaultEndpoint),
        CredentialField(key: "model", label: "Model", placeholder: defaultModel, isSecure: false, isOptional: false, defaultValue: defaultModel),
        CredentialField(key: "apiKey", label: "API Key", placeholder: "sk-... (optional for local)", isSecure: true, isOptional: true, defaultValue: ""),
    ]

    let endpoint: String
    let model: String
    let apiKey: String

    init?(credentials: [String: String]) {
        let endpoint = credentials["endpoint"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = credentials["model"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.endpoint = endpoint?.isEmpty == false ? endpoint! : Self.defaultEndpoint
        self.model = model?.isEmpty == false ? model! : Self.defaultModel
        self.apiKey = credentials["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func toCredentials() -> [String: String] {
        ["endpoint": endpoint, "model": model, "apiKey": apiKey]
    }

    var isValid: Bool { !endpoint.isEmpty && !model.isEmpty }
}
