import Foundation

struct GoogleASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.google
    static let displayName = "Google Gemini"
    static let defaultBaseURL = "https://generativelanguage.googleapis.com/v1beta"
    static let defaultModel = "gemini-2.0-flash"

    static let credentialFields: [CredentialField] = [
        CredentialField(key: "apiKey", label: "API Key", placeholder: "AIza...", isSecure: true, isOptional: false, defaultValue: ""),
        CredentialField(key: "model", label: "Model", placeholder: defaultModel, isSecure: false, isOptional: false, defaultValue: defaultModel),
        CredentialField(key: "baseURL", label: "Base URL", placeholder: defaultBaseURL, isSecure: false, isOptional: true, defaultValue: defaultBaseURL),
    ]

    let apiKey: String
    let model: String
    let baseURL: String

    init?(credentials: [String: String]) {
        guard let apiKey = credentials["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else { return nil }

        let model = credentials["model"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = credentials["baseURL"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.apiKey = apiKey
        self.model = model?.isEmpty == false ? model! : Self.defaultModel
        self.baseURL = baseURL?.isEmpty == false ? baseURL! : Self.defaultBaseURL
    }

    func toCredentials() -> [String: String] {
        ["apiKey": apiKey, "model": model, "baseURL": baseURL]
    }

    var isValid: Bool { !apiKey.isEmpty && !model.isEmpty && !baseURL.isEmpty }
}
