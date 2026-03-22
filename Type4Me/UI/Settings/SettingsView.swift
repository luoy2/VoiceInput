import SwiftUI

// MARK: - Navigation Item

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case vocabulary
    case modes
    case history
    case about

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general:     return L("通用", "General")
        case .vocabulary:  return L("词汇", "Vocabulary")
        case .modes:       return L("模式", "Modes")
        case .history:     return L("历史", "History")
        case .about:       return L("关于", "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general:    return L("快捷键与接口配置", "Hotkeys & API config")
        case .vocabulary:  return L("热词与片段替换", "Hotwords & snippets")
        case .modes:       return L("推理与默认行为", "Processing & defaults")
        case .history:     return L("会话与日志保留", "Sessions & logs")
        case .about:       return L("版本、许可证与支持", "Version, license & support")
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {

    @State private var selectedTab: SettingsTab = .general
    @AppStorage("tf_language") private var language = AppLanguage.systemDefault

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .id(language)
        .frame(minWidth: 700, minHeight: 480)
        .background(TF.settingsBg)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMode)) { note in
            selectedTab = .modes
            if let modeId = note.object as? UUID {
                NotificationCenter.default.post(name: .selectMode, object: modeId)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            VStack(alignment: .leading, spacing: 2) {
                Text("TYPE4ME")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(TF.settingsTextTertiary)
                Text(L("偏好设置", "Preferences"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TF.settingsText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Nav items
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    navItem(tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Footer hint
            Text(L("左侧切换分类\n右侧编辑详情", "Navigate tabs on the left\nEdit details on the right"))
                .font(.system(size: 10))
                .foregroundStyle(TF.settingsTextTertiary)
                .lineSpacing(2)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 180)
        .background(TF.settingsBg)
    }

    private func navItem(_ tab: SettingsTab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? .white : TF.settingsText)
                Text(tab.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? .white.opacity(0.7) : TF.settingsTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? TF.settingsNavActive : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var content: some View {
        ZStack {
            tabPage(.general)    { GeneralSettingsTab() }
            tabPage(.vocabulary) { VocabularyTab() }
            tabPage(.modes)      { ModesSettingsTab() }
            fixedPage(.history)  { HistoryTab(isActive: selectedTab == .history) }
            tabPage(.about)      { AboutTab() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TF.settingsCard)
    }

    /// Scrollable tab page (most tabs).
    private func tabPage<V: View>(_ tab: SettingsTab, @ViewBuilder content: () -> V) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(28)
        }
        .opacity(selectedTab == tab ? 1 : 0)
        .allowsHitTesting(selectedTab == tab)
    }

    /// Fixed-height tab page (no outer scroll, content manages its own scroll).
    private func fixedPage<V: View>(_ tab: SettingsTab, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(selectedTab == tab ? 1 : 0)
        .allowsHitTesting(selectedTab == tab)
    }
}

// MARK: - Reusable Components

struct SettingsSectionHeader: View {
    let label: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(TF.settingsTextTertiary)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(TF.settingsText)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(TF.settingsTextTertiary)
                .lineSpacing(2)
        }
        .padding(.bottom, 16)
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var statusColor: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(TF.settingsText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor ?? TF.settingsTextSecondary)
        }
        .padding(.vertical, 10)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.vertical, 2)
    }
}
