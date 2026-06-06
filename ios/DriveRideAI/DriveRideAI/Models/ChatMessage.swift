import Foundation

/// 聊天消息。可以是纯文本，也可以携带一组出行方案卡片，或一组建议追问的快捷选项。
struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    /// 若该条助手消息包含出行方案，则挂在这里。
    var plans: [CommutePlan]
    /// 助手追问时给出的快捷回复选项（点击即发送）。
    var quickReplies: [String]
    /// 用于「正在输入」动画的占位消息。
    var isTyping: Bool
    let timestamp: Date

    init(role: Role,
         text: String,
         plans: [CommutePlan] = [],
         quickReplies: [String] = [],
         isTyping: Bool = false,
         timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.plans = plans
        self.quickReplies = quickReplies
        self.isTyping = isTyping
        self.timestamp = timestamp
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.isTyping == rhs.isTyping &&
        lhs.plans == rhs.plans &&
        lhs.quickReplies == rhs.quickReplies
    }
}
