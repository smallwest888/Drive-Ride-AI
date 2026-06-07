import SwiftUI

/// 助手「正在输入」的三点跳动动画。
struct TypingIndicatorView: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == index ? 1 : 0.3)
                    .scaleEffect(phase == index ? 1.15 : 0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18, tint: .accentColor, material: .thinMaterial)
        .animation(.easeInOut(duration: 0.25), value: phase)
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

#Preview {
    TypingIndicatorView()
}
