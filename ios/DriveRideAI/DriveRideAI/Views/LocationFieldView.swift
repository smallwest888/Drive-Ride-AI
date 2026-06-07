import SwiftUI

/// 起点 / 终点输入框：左图标 + 文本框 + 可选定位按钮 + 清除/搜索图标。
struct LocationFieldView<Field: Hashable>: View {
    let icon: String
    let iconColor: Color
    let placeholder: String
    @Binding var text: String

    let field: Field
    @FocusState.Binding var focused: Field?

    var showLocate: Bool = false
    var isLocating: Bool = false
    var onLocate: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            TextField(placeholder, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: field)
                .submitLabel(.search)

            if showLocate {
                Button(action: onLocate) {
                    if isLocating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLocating)
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassPanel(cornerRadius: 22, tint: iconColor, material: .thinMaterial)
    }
}
