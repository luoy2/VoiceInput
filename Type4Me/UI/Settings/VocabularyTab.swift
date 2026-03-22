import SwiftUI

struct VocabularyTab: View {

    // Hotwords
    @State private var hotwords: [String] = HotwordStorage.load()
    @State private var newHotword: String = ""

    // Snippets
    @State private var snippets: [(trigger: String, value: String)] = SnippetStorage.load()
    @State private var newTrigger: String = ""
    @State private var newValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(
                label: "VOCABULARY",
                title: L("词汇管理", "Vocabulary"),
                description: L("热词提升识别准确率，片段替换实现语音快捷输入。", "Hotwords improve recognition accuracy. Snippets enable voice shortcuts.")
            )

            // MARK: - Hotwords
            Text(L("ASR 热词", "ASR Hotwords"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TF.settingsText)
                .padding(.bottom, 4)

            Text(L("添加容易被误识别的专有名词，识别引擎会优先匹配。", "Add proper nouns that are often misrecognized. The ASR engine will prioritize them."))
                .font(.system(size: 11))
                .foregroundStyle(TF.settingsTextTertiary)
                .padding(.bottom, 12)

            WrappingHStack(spacing: 6) {
                ForEach(hotwords, id: \.self) { word in
                    hotwordTag(word)
                }

                TextField(L("添加热词...", "Add hotword..."), text: $newHotword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(TF.settingsTextTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .onSubmit { addHotword() }
            }

            Text(L("回车添加，点 × 移除", "Press Enter to add, click x to remove"))
                .font(.system(size: 10))
                .foregroundStyle(TF.settingsTextTertiary)
                .padding(.top, 4)

            // Module separator
            Spacer().frame(height: 20)
            Divider()
            Spacer().frame(height: 20)

            // MARK: - Snippets
            Text(L("片段替换", "Snippets"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TF.settingsText)
                .padding(.bottom, 4)

            Text(L("语音中说到触发词时，最终输出会自动替换为对应内容。", "When a trigger word is spoken, the output is automatically replaced with the corresponding content."))
                .font(.system(size: 11))
                .foregroundStyle(TF.settingsTextTertiary)
                .padding(.bottom, 12)

            // Header
            HStack(spacing: 0) {
                Text(L("触发词", "Trigger"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TF.settingsTextTertiary)
                    .frame(width: 160, alignment: .leading)
                Text(L("替换为", "Replace with"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TF.settingsTextTertiary)
                Spacer()
            }
            .padding(.bottom, 4)

            // Existing snippets
            ForEach(Array(snippets.enumerated()), id: \.offset) { index, snippet in
                snippetRow(index: index, trigger: snippet.trigger, value: snippet.value)
                if index < snippets.count - 1 {
                    SettingsDivider()
                }
            }

            // Add new row
            HStack(spacing: 8) {
                TextField(L("触发词", "Trigger"), text: $newTrigger)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 152)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(TF.settingsTextTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(TF.settingsTextTertiary)

                TextField(L("替换内容", "Replacement"), text: $newValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(TF.settingsTextTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .onSubmit { addSnippet() }

                Button {
                    addSnippet()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TF.settingsAccentGreen)
                }
                .buttonStyle(.plain)
                .disabled(newTrigger.isEmpty || newValue.isEmpty)
            }
            .padding(.top, 8)

            Text(L("示例: \"我的邮箱\" → \"hello@example.com\"", "Example: \"my email\" → \"hello@example.com\""))
                .font(.system(size: 10))
                .foregroundStyle(TF.settingsTextTertiary)
                .padding(.top, 6)

            Spacer()
        }
        .onAppear {
            hotwords = HotwordStorage.load()
            snippets = SnippetStorage.load()
        }
    }

    // MARK: - Hotword Tag

    private func hotwordTag(_ word: String) -> some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.system(size: 12))
                .foregroundStyle(TF.settingsText)
            Button {
                removeHotword(word)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TF.settingsTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(TF.settingsBg)
        )
    }

    // MARK: - Snippet Row

    private func snippetRow(index: Int, trigger: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(trigger)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TF.settingsText)
                .frame(width: 152, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(TF.settingsTextTertiary)

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(TF.settingsTextSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                removeSnippet(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TF.settingsTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func addHotword() {
        let word = newHotword.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !hotwords.contains(word) else {
            newHotword = ""
            return
        }
        hotwords.append(word)
        HotwordStorage.save(hotwords)
        newHotword = ""
    }

    private func removeHotword(_ word: String) {
        hotwords.removeAll { $0 == word }
        HotwordStorage.save(hotwords)
    }

    private func addSnippet() {
        let trigger = newTrigger.trimmingCharacters(in: .whitespaces)
        let value = newValue.trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !value.isEmpty else { return }
        guard !snippets.contains(where: { $0.trigger == trigger }) else { return }
        snippets.append((trigger: trigger, value: value))
        SnippetStorage.save(snippets)
        newTrigger = ""
        newValue = ""
    }

    private func removeSnippet(at index: Int) {
        guard snippets.indices.contains(index) else { return }
        snippets.remove(at: index)
        SnippetStorage.save(snippets)
    }

}
