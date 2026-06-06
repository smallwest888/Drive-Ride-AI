import Foundation

/// 用户出行偏好（默认倾向）。具体某次行程的紧急度由 Agent 从描述中分析。
enum CommutePreference: String, Codable, CaseIterable, Identifiable {
    case balanced   // 综合
    case cheapest   // 省钱优先
    case fastest    // 时间优先
    case greenest   // 环保优先

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return "综合推荐"
        case .cheapest: return "省钱优先"
        case .fastest: return "时间优先"
        case .greenest: return "环保优先"
        }
    }
}

/// 用户出行信息：是否有车、车型、交通卡、默认偏好。可持久化。
struct UserProfile: Codable, Equatable {
    /// 是否拥有可用车辆。无车则不生成自驾 / P+R 方案。
    var hasCar: Bool
    var car: CarProfile
    var transitCard: TransitCard
    var preference: CommutePreference

    static let `default` = UserProfile(
        hasCar: true,
        car: .default,
        transitCard: .storedValue,
        preference: .balanced
    )
}
