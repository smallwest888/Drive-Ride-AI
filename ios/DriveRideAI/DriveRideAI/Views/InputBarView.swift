import SwiftUI

/// 底部输入栏。
struct InputBarView: View {
    @Binding var text: String
    var isProcessing: Bool
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom) {
                TextField("描述你的出行需求…", text: $text, axis: .vertical)
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
                Image(systemName: isProcessing ? "ellipsis" : "arrow.up")
                    .font(.system(size: 18, weight: .bold))
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
