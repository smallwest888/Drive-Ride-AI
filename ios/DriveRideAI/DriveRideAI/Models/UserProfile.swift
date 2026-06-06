import Foundation

/// 用户出行偏好（默认倾向）。具体某次行程的紧急度由 Agent 从描述中分析。
enum CommutePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced   // 综合
    case cheapest   // 省钱优先
    case fastest    // 时间优先
    case greenest   // 环保优先

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return tr("综合推荐", "Balanced")
        case .cheapest: return tr("省钱优先", "Cheapest")
        case .fastest: return tr("时间优先", "Fastest")
        case .greenest: return tr("环保优先", "Greenest")
        }
    }
}

/// 用户出行信息：是否有车、车型、德国公共交通票种、默认偏好。可持久化。
///
/// 关于价格：苹果 / MapKit 不提供公交票价与停车费数据。
/// 公交票价不在输入页填写；后台 AI 只查询票种适用范围并辅助判断，不编造票价。
/// 停车费不由用户填写，规划时由后台 AI 联网搜索；搜不到则不计入总价。
/// 自驾油 / 电费由车辆能耗 × 能源单价 × MapKit 真实里程算出，本身即真实。
struct UserProfile: Codable, Equatable, Sendable {
    /// 是否拥有可用车辆。无车则不生成自驾 / P+R 方案。
    var hasCar: Bool
    var car: CarProfile
    var transitCard: TransitCard
    var preference: CommutePreference

    /// 旧版本曾允许手填公交单程票价；保留字段仅为兼容本地存档，当前输入页不再展示。
    var transitFarePerRide: Double?
    /// 旧版本曾允许手填市区停车费；保留字段仅为兼容本地存档，当前输入页不再展示。
    var cityParkingFee: Double?
    /// 旧版本曾允许手填 P+R 停车费；保留字段仅为兼容本地存档，当前输入页不再展示。
    var parkRideParkingFee: Double?

    /// 后台 AI 设置（可选，默认关闭）。nil = 未配置。
    var ai: AISettings?

    static let `default` = UserProfile(
        hasCar: true,
        car: .default,
        transitCard: .storedValue,
        preference: .balanced
    )
}
