import Foundation
import SwiftUI

/// 主界面状态：起终点字段、聊天记录、调用 Agent 规划。
@MainActor
final class PlannerViewModel: ObservableObject {
    @Published var originText: String = ""
    @Published var destinationText: String = ""
    @Published var inputText: String = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isProcessing: Bool = false

    private let planner = CommutePlanner()
    private var profileProvider: () -> UserProfile

    init(profileProvider: @escaping () -> UserProfile = { .default }) {
        self.profileProvider = profileProvider
        appendWelcome()
    }

    func updateProfileProvider(_ provider: @escaping () -> UserProfile) {
        self.profileProvider = provider
    }

    private func appendWelcome() {
        messages.append(
            ChatMessage(
                role: .assistant,
                text: "你好，我是 Drive&Ride 出行助手 🅿️🚇\n填好上方的出发地、目的地，再描述一下需求（比如「有点赶时间」「想省钱」），我会帮你比较公交、自驾、P+R 换乘的成本和时间，给出几种方案。"
            )
        )
    }

    /// 用户点击「规划 / 发送」。
    func submit() {
        let extra = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        // 组合一条用户可见消息：起终点 + 额外需求。
        let userVisible = composeUserMessage(extra: extra)
        if !userVisible.isEmpty {
            messages.append(ChatMessage(role: .user, text: userVisible))
        }

        runPlanning(extraText: extra)
    }

    /// 点击快捷追问选项。
    func sendQuickReply(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text))
        runPlanning(extraText: text)
    }

    private func composeUserMessage(extra: String) -> String {
        var parts: [String] = []
        let o = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty || !d.isEmpty {
            parts.append("\(o.isEmpty ? "（未填）" : o) → \(d.isEmpty ? "（未填）" : d)")
        }
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: "　·　")
    }

    private func runPlanning(extraText: String) {
        guard !isProcessing else { return }

        let typing = ChatMessage(role: .assistant, text: "", isTyping: true)
        messages.append(typing)
        isProcessing = true

        let input = PlanningInput(
            origin: makeLocation(originText),
            destination: makeLocation(destinationText),
            userText: combinedUserText(extra: extraText),
            profile: profileProvider()
        )

        Task {
            // 轻微延迟，呈现「思考中」的体验。
            try? await Task.sleep(nanoseconds: 450_000_000)
            let outcome = planner.plan(input)

            messages.removeAll { $0.id == typing.id }

            // 回填 Agent 解析出的起终点。
            if let o = outcome.resolvedOrigin, originText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                originText = o
            }
            if let d = outcome.resolvedDestination, destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destinationText = d
            }

            messages.append(
                ChatMessage(role: .assistant,
                            text: outcome.assistantText,
                            plans: outcome.plans,
                            quickReplies: outcome.quickReplies)
            )
            isProcessing = false
        }
    }

    private func combinedUserText(extra: String) -> String {
        var parts: [String] = []
        let o = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { parts.append("从\(o)") }
        if !d.isEmpty { parts.append("到\(d)") }
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: " ")
    }

    private func makeLocation(_ text: String) -> TripLocation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : TripLocation(name: trimmed)
    }

    func reset() {
        messages.removeAll()
        appendWelcome()
    }
}
