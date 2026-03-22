import Foundation

struct OpenAIASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.openai
    static let displayName = "OpenAI Whisper"

    static let credentialFields: [CredentialField] = [
        CredentialField(key: "apiKey", label: "API Key", placeholder: "sk-...", isSecure: true, isOptional: false, defaultValue: ""),
        CredentialField(key: "baseURL", label: "Base URL", placeholder: "https://api.openai.com/v1", isSecure: false, isOptional: true, defaultValue: "https://api.openai.com/v1"),
    ]

    let apiKey: String
    let baseURL: String

    init?(credentials: [String: String]) {
        guard let key = credentials["apiKey"], !key.isEmpty else { return nil }
        self.apiKey = key
        self.baseURL = credentials["baseURL"]?.isEmpty == false
            ? credentials["baseURL"]!
            : "https://api.openai.com/v1"
    }

    func toCredentials() -> [String: String] {
        ["apiKey": apiKey, "baseURL": baseURL]
    }

    var isValid: Bool { !apiKey.isEmpty }
}
