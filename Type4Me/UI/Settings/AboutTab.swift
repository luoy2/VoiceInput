import SwiftUI

struct AboutTab: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(
                label: "ABOUT",
                title: L("关于 Type4Me", "About Type4Me"),
                description: L("语音，流畅输入。基于火山引擎大模型语音识别的 macOS 原生输入工具。", "Voice to text, seamlessly. A native macOS input tool powered by large-model ASR.")
            )

            Spacer().frame(height: 8)

            // App info rows
            SettingsRow(label: L("版本", "Version"), value: appVersion)
            SettingsDivider()
            SettingsRow(label: L("构建", "Build"), value: buildNumber)
            SettingsDivider()
            SettingsRow(label: L("平台", "Platform"), value: "macOS 14+")
            SettingsDivider()
            SettingsRow(label: L("引擎", "Engine"), value: L("火山引擎 Doubao Bigmodel", "Volcano Doubao Bigmodel"))
            SettingsDivider()
            SettingsRow(label: L("许可证", "License"), value: "MIT")

            Spacer().frame(height: 24)

            // Links
            HStack(spacing: 12) {
                linkButton("GitHub", icon: "chevron.left.forwardslash.chevron.right") {
                    if let url = URL(string: "https://github.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                linkButton(L("反馈", "Feedback"), icon: "envelope") {
                    if let url = URL(string: "https://github.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Spacer()

            // Footer
            Text("Made with ♥ and Claude Code")
                .font(.system(size: 10))
                .foregroundStyle(TF.settingsTextTertiary)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func linkButton(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TF.settingsText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(TF.settingsBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(TF.settingsTextTertiary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
