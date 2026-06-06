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
        case .balanced: return tr("综合推荐", "Balanced")
        case .cheapest: return tr("省钱优先", "Cheapest")
        case .fastest: return tr("时间优先", "Fastest")
        case .greenest: return tr("环保优先", "Greenest")
        }
    }
}

/// 用户出行信息：是否有车、车型、交通卡、默认偏好、真实价格。可持久化。
///
/// 关于价格：苹果 / MapKit 不提供公交票价与停车费数据，因此这两类价格不能自动取真值。
/// 这里改为由用户填写其所在城市的**真实价格**（可选）。未填的项不计入总价，绝不编造。
/// 自驾油 / 电费由车辆能耗 × 能源单价 × MapKit 真实里程算出，本身即真实。
struct UserProfile: Codable, Equatable {
    /// 是否拥有可用车辆。无车则不生成自驾 / P+R 方案。
    var hasCar: Bool
    var car: CarProfile
    var transitCard: TransitCard
    var preference: CommutePreference

    /// 公交单程基础票价（元，真实值，用户填写）。配合交通卡折扣使用。nil = 未填。
    var transitFarePerRide: Double?
    /// 自驾到市区的停车费（元，一口价，真实值）。nil = 未填。
    var cityParkingFee: Double?
    /// P+R 换乘停车场停车费（元，真实值）。nil = 未填。
    var parkRideParkingFee: Double?

    static let `default` = UserProfile(
        hasCar: true,
        car: .default,
        transitCard: .storedValue,
        preference: .balanced
    )
}
