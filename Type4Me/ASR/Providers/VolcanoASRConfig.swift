import Foundation

struct VolcanoASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.volcano
    static var displayName: String { L("火山引擎 (Doubao)", "Volcano (Doubao)") }

    static var credentialFields: [CredentialField] {[
        CredentialField(key: "accessKey", label: "API Key", placeholder: L("豆包语音 API Key", "Doubao Speech API Key"), isSecure: true, isOptional: false, defaultValue: ""),
    ]}

    let accessKey: String   // x-api-key for v3 API
    let uid: String

    init?(credentials: [String: String]) {
        guard let accessKey = credentials["accessKey"], !accessKey.isEmpty
        else { return nil }
        self.accessKey = accessKey
        self.uid = ASRIdentityStore.loadOrCreateUID()
    }

    func toCredentials() -> [String: String] {
        ["accessKey": accessKey]
    }

    var isValid: Bool {
        !accessKey.isEmpty
    }
}
