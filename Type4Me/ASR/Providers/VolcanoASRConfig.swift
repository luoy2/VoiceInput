import Foundation

struct VolcanoASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.volcano
    static var displayName: String { L("火山引擎 (Doubao)", "Volcano (Doubao)") }

    static var credentialFields: [CredentialField] {[
        CredentialField(key: "appKey", label: "App Key", placeholder: "APPID", isSecure: false, isOptional: false, defaultValue: ""),
        CredentialField(key: "accessKey", label: "Access Token", placeholder: L("访问令牌", "Access token"), isSecure: true, isOptional: false, defaultValue: ""),
    ]}

    let appKey: String
    let accessKey: String
    let resourceId: String
    let uid: String

    init?(credentials: [String: String]) {
        guard let appKey = credentials["appKey"], !appKey.isEmpty,
              let accessKey = credentials["accessKey"], !accessKey.isEmpty
        else { return nil }
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = credentials["resourceId"]?.isEmpty == false
            ? credentials["resourceId"]!
            : "volc.bigasr.sauc.duration"
        self.uid = ASRIdentityStore.loadOrCreateUID()
    }

    func toCredentials() -> [String: String] {
        ["appKey": appKey, "accessKey": accessKey, "resourceId": resourceId]
    }

    var isValid: Bool {
        !appKey.isEmpty && !accessKey.isEmpty
    }
}
