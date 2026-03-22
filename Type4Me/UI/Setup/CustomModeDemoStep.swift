import SwiftUI

struct CustomModeDemoStep: View {

    // MARK: - Demo Text

    private var rawText: String {
        L("帮我分析英伟达最近一年的股价走势给我完整的分析报告",
          "Analyze NVIDIA stock price trends over the past year and give me a full report")
    }
    private var processedText: String {
        L("请分析英伟达（NVDA）最近一年的股价走势，包括：\n1. 关键价格节点与涨跌幅\n2. 主要驱动因素（财报、AI需求、市场情绪）\n3. 技术面支撑与阻力位\n4. 未来走势预判\n\n请给出完整的分析报告。",
          "Please analyze NVIDIA (NVDA) stock price trends over the past year, including:\n1. Key price points and percentage changes\n2. Main drivers (earnings, AI demand, market sentiment)\n3. Technical support and resistance levels\n4. Future outlook\n\nPlease provide a comprehensive analysis report.")
    }

    // MARK: - Animation State

    @State private var rawReveal: Int = 0
    @State private var processedReveal: Int = 0
    @State private var showProcessed: Bool = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Title
            VStack(spacing: 6) {
                Text(L("自定义模式", "Custom Mode"))
                    .font(.system(size: 22, weight: .bold))
                Text(L("说普通话，出专业文本", "Speak naturally, get polished text"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 4)

            // Cards
            VStack(spacing: 12) {
                // Raw card
                demoCard(
                    label: L("你说的", "You said"),
                    icon: "waveform",
                    text: String(rawText.prefix(rawReveal)),
                    background: TF.settingsBg,
                    textColor: TF.settingsTextTertiary,
                    accentBorder: false
                )

                // Arrow
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TF.amber)
                    .opacity(showProcessed ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: showProcessed)

                // Processed card
                demoCard(
                    label: L("粘贴的", "Pasted"),
                    icon: "doc.text",
                    text: String(processedText.prefix(processedReveal)),
                    background: TF.settingsCard,
                    textColor: TF.settingsText,
                    accentBorder: showProcessed
                )
                .opacity(showProcessed ? 1.0 : 0.4)
                .animation(.easeInOut(duration: 0.4), value: showProcessed)
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .onAppear { startAnimation() }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    // MARK: - Card View

    private func demoCard(
        label: String,
        icon: String,
        text: String,
        background: Color,
        textColor: Color,
        accentBorder: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(textColor.opacity(0.6))

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accentBorder ? TF.amber : .clear, lineWidth: 1.5)
        )
    }

    // MARK: - Animation Loop

    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task {
            while !Task.isCancelled {
                // Reset
                rawReveal = 0
                processedReveal = 0
                showProcessed = false

                // Phase 1: type raw text
                for i in 1...rawText.count {
                    guard !Task.isCancelled else { return }
                    rawReveal = i
                    try? await Task.sleep(for: .milliseconds(60))
                }

                // Pause
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }

                // Phase 2: fade in processed card, then type processed text
                showProcessed = true
                for i in 1...processedText.count {
                    guard !Task.isCancelled else { return }
                    processedReveal = i
                    try? await Task.sleep(for: .milliseconds(30))
                }

                // Phase 3: hold
                try? await Task.sleep(for: .milliseconds(3000))
                guard !Task.isCancelled else { return }

                // Fade out and pause before next loop
                withAnimation(.easeOut(duration: 0.4)) {
                    showProcessed = false
                    rawReveal = 0
                    processedReveal = 0
                }
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }
    }
}
