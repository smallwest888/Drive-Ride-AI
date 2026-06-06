import Foundation

/// 聊天消息。可以是纯文本，也可以携带一组出行方案卡片。
struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    /// 若该条助手消息包含出行方案，则挂在这里。
    var plans: [TravelPlan]
    /// 用于「正在输入」动画的占位消息。
    var isTyping: Bool
    let timestamp: Date

    init(role: Role,
         text: String,
         plans: [TravelPlan] = [],
         isTyping: Bool = false,
         timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.plans = plans
        self.isTyping = isTyping
        self.timestamp = timestamp
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.isTyping == rhs.isTyping &&
        lhs.plans == rhs.plans
    }
}
