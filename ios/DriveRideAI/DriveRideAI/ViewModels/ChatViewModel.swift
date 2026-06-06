import Foundation
import SwiftUI

/// 聊天界面的状态管理。
@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published private(set) var isProcessing: Bool = false

    private let planner: TripPlanning

    /// 引导提示词，点击即可快速发送。
    let suggestions: [String] = [
        "我想从北京去上海，预算有限，周五出发",
        "成都到重庆，两个人，想快点到",
        "广州去深圳，舒适一点",
        "杭州到南京，最环保的方式"
    ]

    init(planner: TripPlanning = AITripPlanner()) {
        self.planner = planner
        appendWelcome()
    }

    private func appendWelcome() {
        messages.append(
            ChatMessage(
                role: .assistant,
                text: "你好，我是你的 AI 出行助手 🚗✈️\n告诉我你想去哪、从哪出发，以及偏好（省钱 / 快 / 舒适），我会帮你比较飞机、高铁、自驾、大巴等方式的成本和时间，给出几种方案。"
            )
        )
    }

    func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        send(text)
    }

    func send(_ text: String) {
        guard !isProcessing else { return }
        messages.append(ChatMessage(role: .user, text: text))

        let typing = ChatMessage(role: .assistant, text: "", isTyping: true)
        messages.append(typing)
        isProcessing = true

        Task {
            let result = try? await planner.plan(for: text)
            removeTyping(id: typing.id)

            if let result {
                messages.append(
                    ChatMessage(role: .assistant, text: result.assistantText, plans: result.plans)
                )
            } else {
                messages.append(
                    ChatMessage(role: .assistant, text: "抱歉，刚刚分析出了点问题，可以再描述一次你的行程吗？")
                )
            }
            isProcessing = false
        }
    }

    private func removeTyping(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    func reset() {
        messages.removeAll()
        appendWelcome()
    }
}
