import Foundation
import SwiftUI
import MapKit

/// 主界面状态：起终点（真实地点）、聊天记录、调用 Agent 规划。
@MainActor
final class PlannerViewModel: ObservableObject {
    @Published var originText: String = ""
    @Published var destinationText: String = ""
    @Published var inputText: String = ""
    @Published var originPlace: ResolvedPlace?
    @Published var destinationPlace: ResolvedPlace?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isProcessing: Bool = false

    private let planner = CommutePlanner()
    /// 仅用于把自由文本解析成坐标（与界面联想用的实例分离）。
    private let resolver = LocationSearchService()
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
                text: tr(
                    "你好，我是 Drive&Ride 出行助手 🅿️🚇\n在上方搜索真实的出发地、目的地（或点定位用当前位置），再描述需求（如「有点赶」「想省钱」）。我会用 Apple 地图的实时路线，比较公交、自驾、P+R 换乘的成本和时间，并支持一键导航。",
                    "Hi, I'm your Drive&Ride assistant 🅿️🚇\nSearch a real origin and destination above (or tap locate for your current position), then describe your needs (e.g. \"a bit rushed\", \"save money\"). I use Apple Maps live routing to compare transit, driving, and Park & Ride by cost and time — with one-tap navigation."
                )
            )
        )
    }

    func setOrigin(_ place: ResolvedPlace) {
        originPlace = place
        originText = place.name
    }

    func setDestination(_ place: ResolvedPlace) {
        destinationPlace = place
        destinationText = place.name
    }

    /// 用户编辑了输入框文本：若与已选地点名不一致，则使已解析地点失效。
    func originTextChanged() {
        if originPlace?.name != originText { originPlace = nil }
    }

    func destinationTextChanged() {
        if destinationPlace?.name != destinationText { destinationPlace = nil }
    }

    func submit() {
        let extra = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        let userVisible = composeUserMessage(extra: extra)
        if !userVisible.isEmpty {
            messages.append(ChatMessage(role: .user, text: userVisible))
        }
        runPlanning(extraText: extra)
    }

    func sendQuickReply(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text))
        runPlanning(extraText: text)
    }

    private func composeUserMessage(extra: String) -> String {
        var parts: [String] = []
        let o = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty || !d.isEmpty {
            let blank = tr("（未填）", "(empty)")
            parts.append("\(o.isEmpty ? blank : o) → \(d.isEmpty ? blank : d)")
        }
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: tr("　·　", "  ·  "))
    }

    private func runPlanning(extraText: String) {
        guard !isProcessing else { return }

        let typing = ChatMessage(role: .assistant, text: "", isTyping: true)
        messages.append(typing)
        isProcessing = true

        Task {
            // 文本已填但未通过联想选择时，尝试解析为真实坐标。
            if originPlace == nil, !originText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                originPlace = await resolver.resolve(query: originText)
            }
            if destinationPlace == nil, !destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destinationPlace = await resolver.resolve(query: destinationText,
                                                          near: originPlace?.coordinate)
            }

            let input = PlanningInput(origin: originPlace,
                                      destination: destinationPlace,
                                      userText: extraText,
                                      profile: profileProvider())
            let outcome = await planner.plan(input)

            messages.removeAll { $0.id == typing.id }
            messages.append(
                ChatMessage(role: .assistant, text: outcome.assistantText,
                            plans: outcome.plans, quickReplies: outcome.quickReplies)
            )
            isProcessing = false
        }
    }

    func reset() {
        messages.removeAll()
        appendWelcome()
    }

    func refreshWelcomeIfIdle() {
        guard messages.count <= 1, !isProcessing else { return }
        messages.removeAll()
        appendWelcome()
    }
}
