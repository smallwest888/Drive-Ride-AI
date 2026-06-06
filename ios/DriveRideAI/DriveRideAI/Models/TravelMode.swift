import SwiftUI

/// 出行方式。每种方式带有展示用的图标、配色与基础特征参数。
enum TravelMode: String, CaseIterable, Identifiable, Codable {
    case flight     // 飞机
    case highSpeedRail // 高铁
    case train      // 普通火车
    case driving    // 自驾
    case coach      // 长途大巴
    case rideHailing // 网约车/出租

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flight: return "飞机"
        case .highSpeedRail: return "高铁"
        case .train: return "火车"
        case .driving: return "自驾"
        case .coach: return "大巴"
        case .rideHailing: return "网约车"
        }
    }

    var systemImage: String {
        switch self {
        case .flight: return "airplane"
        case .highSpeedRail: return "tram.fill"
        case .train: return "tram"
        case .driving: return "car.fill"
        case .coach: return "bus.fill"
        case .rideHailing: return "car.side.fill"
        }
    }

    var tint: Color {
        switch self {
        case .flight: return .blue
        case .highSpeedRail: return .green
        case .train: return .teal
        case .driving: return .orange
        case .coach: return .purple
        case .rideHailing: return .pink
        }
    }

    // MARK: - 估算参数（用于本地启发式规划引擎）

    /// 平均巡航/行驶速度（km/h）。
    var averageSpeedKmh: Double {
        switch self {
        case .flight: return 750
        case .highSpeedRail: return 280
        case .train: return 110
        case .driving: return 90
        case .coach: return 80
        case .rideHailing: return 70
        }
    }

    /// 每公里参考票价/成本（元/km）。
    var costPerKm: Double {
        switch self {
        case .flight: return 0.85
        case .highSpeedRail: return 0.48
        case .train: return 0.22
        case .driving: return 0.75   // 油费 + 过路费 + 折旧的综合估算
        case .coach: return 0.30
        case .rideHailing: return 2.6
        }
    }

    /// 固定附加耗时（小时）：值机/安检、进出站、取还车等。
    var fixedOverheadHours: Double {
        switch self {
        case .flight: return 2.5
        case .highSpeedRail: return 0.8
        case .train: return 0.6
        case .driving: return 0.3
        case .coach: return 0.5
        case .rideHailing: return 0.1
        }
    }

    /// 舒适度评分（0~5）。
    var comfortScore: Double {
        switch self {
        case .flight: return 4.0
        case .highSpeedRail: return 4.5
        case .train: return 3.0
        case .driving: return 4.2
        case .coach: return 2.5
        case .rideHailing: return 4.0
        }
    }

    /// 每公里碳排放（kg CO₂ / km，单人估算）。
    var carbonPerKm: Double {
        switch self {
        case .flight: return 0.18
        case .highSpeedRail: return 0.04
        case .train: return 0.06
        case .driving: return 0.17
        case .coach: return 0.07
        case .rideHailing: return 0.16
        }
    }

    /// 该方式适用的最大合理距离（km）。超过则一般不推荐。
    var maxReasonableDistanceKm: Double {
        switch self {
        case .flight: return .greatestFiniteMagnitude
        case .highSpeedRail: return 2200
        case .train: return 3000
        case .driving: return 1500
        case .coach: return 800
        case .rideHailing: return 200
        }
    }

    /// 该方式适用的最小合理距离（km）。低于则一般不划算/不必要。
    var minReasonableDistanceKm: Double {
        switch self {
        case .flight: return 400
        case .highSpeedRail: return 80
        case .train: return 60
        case .driving: return 0
        case .coach: return 30
        case .rideHailing: return 0
        }
    }
}
