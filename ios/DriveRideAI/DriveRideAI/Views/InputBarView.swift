import SwiftUI

/// 底部需求输入栏。
struct InputBarView: View {
    @Binding var text: String
    var isProcessing: Bool
    var placeholder: String = "描述你的出行需求…"
    var sendIcon: String = "arrow.up"
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        // 允许在仅填写了起终点、未输入额外需求时也能触发规划。
        !isProcessing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...4)
                    .font(.body)
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button(action: onSend) {
                Image(systemName: isProcessing ? "ellipsis" : sendIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(canSend ? Color.accentColor : Color.gray.opacity(0.4))
                    )
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    InputBarView(text: .constant(""), isProcessing: false, onSend: {})
}
