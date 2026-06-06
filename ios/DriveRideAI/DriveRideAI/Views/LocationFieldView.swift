import SwiftUI

/// 起点 / 终点输入框（参考设计：左侧图标 + 文本框 + 右侧搜索图标）。
struct LocationFieldView: View {
    let icon: String
    let iconColor: Color
    let placeholder: String
    @Binding var text: String

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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        LocationFieldView(icon: "location.fill", iconColor: .blue,
                          placeholder: "输入出发地", text: .constant(""))
        LocationFieldView(icon: "flag.fill", iconColor: .red,
                          placeholder: "输入目的地", text: .constant("公司"))
    }
    .padding()
}
