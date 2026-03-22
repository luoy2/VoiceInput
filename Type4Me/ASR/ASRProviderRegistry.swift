import Foundation

enum ASRProviderRegistry {

    struct ProviderEntry: Sendable {
        let configType: any ASRProviderConfig.Type
        let createClient: (@Sendable () -> any SpeechRecognizer)?

        var isAvailable: Bool { createClient != nil }
    }

    static let all: [ASRProvider: ProviderEntry] = [
        .volcano: ProviderEntry(configType: VolcanoASRConfig.self, createClient: { VolcASRClient() }),
        .openai:  ProviderEntry(configType: OpenAIASRConfig.self,  createClient: nil),
        .azure:   ProviderEntry(configType: AzureASRConfig.self,   createClient: nil),
        .google:  ProviderEntry(configType: GoogleASRConfig.self,  createClient: nil),
        .aws:     ProviderEntry(configType: AWSASRConfig.self,     createClient: nil),
        .aliyun:  ProviderEntry(configType: AliyunASRConfig.self,  createClient: nil),
        .tencent: ProviderEntry(configType: TencentASRConfig.self, createClient: nil),
        .iflytek: ProviderEntry(configType: IflytekASRConfig.self, createClient: nil),
        .custom:  ProviderEntry(configType: CustomASRConfig.self,  createClient: nil),
    ]

    static func entry(for provider: ASRProvider) -> ProviderEntry? {
        all[provider]
    }

    static func configType(for provider: ASRProvider) -> (any ASRProviderConfig.Type)? {
        all[provider]?.configType
    }

    static func createClient(for provider: ASRProvider) -> (any SpeechRecognizer)? {
        all[provider]?.createClient?()
    }
}
