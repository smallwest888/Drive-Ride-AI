import Foundation

/// 用户出行偏好。
enum TripPreference: String, Codable {
    case cheapest    // 最省钱
    case fastest     // 最快
    case comfortable // 最舒适
    case greenest    // 最环保
    case balanced    // 综合

    var displayName: String {
        switch self {
        case .cheapest: return "省钱优先"
        case .fastest: return "时间优先"
        case .comfortable: return "舒适优先"
        case .greenest: return "环保优先"
        case .balanced: return "综合推荐"
        }
    }
}

/// 从用户自然语言中解析出的出行需求。
struct TripRequest: Equatable {
    var origin: String?
    var destination: String?
    /// 估算直线/路网距离（km）。
    var distanceKm: Double?
    var preference: TripPreference
    var passengers: Int
    /// 预算上限（元），可为空。
    var budget: Double?
    /// 原始输入文本。
    var rawText: String

    var isResolvable: Bool {
        destination != nil && (distanceKm ?? 0) > 0
    }
}
