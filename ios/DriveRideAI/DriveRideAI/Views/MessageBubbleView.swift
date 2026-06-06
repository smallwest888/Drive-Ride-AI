import SwiftUI

/// 一条聊天消息（含可能的方案卡片）。
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    // MARK: - 用户消息（右对齐，强调色气泡）

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

    // MARK: - 助手消息（左对齐，含头像与方案卡片）

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
                    if !message.plans.isEmpty {
                        ForEach(Array(message.plans.enumerated()), id: \.element.id) { index, plan in
                            PlanCardView(plan: plan, rank: index + 1)
                        }
                    }
                }
            }
            Spacer(minLength: 16)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(message: ChatMessage(role: .user, text: "我想从北京去上海，预算有限"))
            MessageBubbleView(message: ChatMessage(
                role: .assistant,
                text: "已为你分析北京 → 上海，下面是几种方案 👇",
                plans: [
                    TravelPlan(mode: .highSpeedRail, cost: 553, durationHours: 5.3, comfortScore: 4.5, carbonKg: 46, highlight: "推荐", summary: "市中心直达，准点率高。"),
                    TravelPlan(mode: .train, cost: 253, durationHours: 12, comfortScore: 3, carbonKg: 69, highlight: "最省钱", summary: "票价最低，适合预算紧。")
                ]
            ))
            MessageBubbleView(message: ChatMessage(role: .assistant, text: "", isTyping: true))
        }
        .padding()
    }
}
