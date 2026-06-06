import SwiftUI

/// 一条聊天消息（含可能的方案卡片与快捷追问选项）。
struct MessageBubbleView: View {
    let message: ChatMessage
    var onQuickReply: (String) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 10) {
                if message.isTyping {
                    TypingIndicatorView()
                } else {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(message.plans.enumerated()), id: \.element.id) { index, plan in
                        PlanCardView(plan: plan, rank: index + 1)
                    }
                    if !message.quickReplies.isEmpty {
                        quickReplies
                    }
                }
            }
            Spacer(minLength: 16)
        }
    }

    private var quickReplies: some View {
        FlexibleChips(items: message.quickReplies) { reply in
            Button {
                onQuickReply(reply)
            } label: {
                Text(reply)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 30, height: 30)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// 简单的自动换行标签容器。
struct FlexibleChips<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    /// 每行最多放 2 个，避免超宽。
    private func rows() -> [[String]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(message: ChatMessage(role: .user, text: "家 → 公司　·　有点赶"))
            MessageBubbleView(message: ChatMessage(
                role: .assistant,
                text: "我已记录行程。方便告诉我大致距离吗？",
                quickReplies: ["约 5 公里", "约 15 公里", "约 30 公里", "约 50 公里"]
            ))
            MessageBubbleView(message: ChatMessage(role: .assistant, text: "", isTyping: true))
        }
        .padding()
    }
}
