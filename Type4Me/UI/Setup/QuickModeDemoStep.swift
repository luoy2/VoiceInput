import SwiftUI

/// Setup wizard step demonstrating "快速模式" with a live FloatingBarView animation.
struct QuickModeDemoStep: View {

    @State private var demoState = DemoState()

    var body: some View {
        VStack(spacing: TF.spacingXL) {
            Spacer()

            // Title + subtitle
            VStack(spacing: TF.spacingSM) {
                Text(L("快速模式", "Quick Mode"))
                    .font(.system(size: 22, weight: .bold))
                Text(L("按住说话，松开输入", "Hold to speak, release to type"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Dark simulated desktop with FloatingBarView
            ZStack {
                RoundedRectangle(cornerRadius: TF.cornerLG)
                    .fill(Color(white: 0.12))

                FloatingBarView<DemoState>(state: demoState)
                    .frame(maxWidth: 420)
            }
            .frame(height: 160)
            .padding(.horizontal, 48)

            // Description
            Text(L("语音实时转写，结果直接粘贴到光标位置", "Real-time transcription, pasted directly at cursor"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .onAppear { demoState.startQuickModeDemo() }
        .onDisappear { demoState.stop() }
    }
}
