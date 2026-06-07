import SwiftUI
import MapKit

/// 一段可用 Apple 地图发起的真实导航。
struct NavLeg: Identifiable {
    let id = UUID()
    let label: String
    let source: MKMapItem
    let destination: MKMapItem
    let transport: MKDirectionsTransportType
    let polyline: MKPolyline?

    var displayLabel: String {
        switch label {
        case "驾车到 P+R", "驾车到换乘点":
            return tr("驾车到 P+R", "Drive to P+R")
        case "公共交通", "换乘进城":
            return tr("公共交通", "Public transit")
        case "驾车":
            return tr("驾车", "Driving")
        default:
            return label
        }
    }

    /// 在 Apple 地图中打开该段导航。
    func openInAppleMaps() {
        let mode: String
        switch transport {
        case .automobile: mode = MKLaunchOptionsDirectionsModeDriving
        case .walking: mode = MKLaunchOptionsDirectionsModeWalking
        case .transit: mode = MKLaunchOptionsDirectionsModeTransit
        default: mode = MKLaunchOptionsDirectionsModeDriving
        }
        MKMapItem.openMaps(with: [source, destination],
                           launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
}

/// 行程紧急程度，由 Agent 从用户描述中分析得出。
enum Urgency: String, Codable {
    case relaxed   // 不赶时间
    case normal    // 正常
    case urgent    // 很赶

    var displayName: String {
        switch self {
        case .relaxed: return tr("不赶时间", "no rush")
        case .normal: return tr("正常", "normal pace")
        case .urgent: return tr("时间紧迫", "in a hurry")
        }
    }
}

/// 方案大类。
enum CommuteMode: String, Codable, Identifiable {
    case transit       // 全程公共交通
    case car           // 全程自驾
    case parkAndRide   // P+R：自驾到换乘停车场 + 公共交通

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transit: return tr("全程公交", "Public Transit")
        case .car: return tr("全程自驾", "Driving")
        case .parkAndRide: return tr("P+R 换乘", "Park & Ride")
        }
    }

    var systemImage: String {
        switch self {
        case .transit: return "tram.fill"
        case .car: return "car.fill"
        case .parkAndRide: return "p.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .transit: return .green
        case .car: return .orange
        case .parkAndRide: return .blue
        }
    }
}

/// 单个分段的出行方式。
enum SegmentMode: String, Codable {
    case drive   // 驾车
    case bus     // 公交
    case subway  // 地铁
    case walk    // 步行
    case park    // 停车换乘

    var displayName: String {
        switch self {
        case .drive: return tr("驾车", "Drive")
        case .bus: return tr("公交", "Bus")
        case .subway: return tr("地铁", "Metro")
        case .walk: return tr("步行", "Walk")
        case .park: return tr("停车换乘", "Park & switch")
        }
    }

    var systemImage: String {
        switch self {
        case .drive: return "car.fill"
        case .bus: return "bus.fill"
        case .subway: return "tram.fill"
        case .walk: return "figure.walk"
        case .park: return "parkingsign"
        }
    }
}

/// 行程中的一段。
struct PlanSegment: Identifiable, Equatable {
    let id = UUID()
    let mode: SegmentMode
    /// 该段描述，如「驾车至 P+R 停车场」。
    let detail: String
    let distanceKm: Double
    let durationHours: Double
    let cost: Double
    /// 目的地货币代码（如 "CNY"、"USD"）。
    var currencyCode: String = CurrencyFormat.deviceCurrencyCode
    /// 可选出发时间（用于公共交通）。
    var departureDate: Date?

    var displayDetail: String {
        switch mode {
        case .drive:
            if detail.hasPrefix("驾车至「"), detail.hasSuffix("」") {
                let name = detail
                    .dropFirst("驾车至「".count)
                    .dropLast()
                return tr(detail, "Drive to \(name)")
            }
            return localizedFixedDetail
        case .park, .bus, .subway, .walk:
            return localizedFixedDetail
        }
    }

    private var localizedFixedDetail: String {
        switch detail {
        case "停车换乘":
            return tr("停车换乘", "Park & switch")
        case "停车换乘（未查到）":
            return tr("停车换乘（未查到）", "Park & switch (not found)")
        case "停车换乘（联网搜索）":
            return tr("停车换乘（联网搜索）", "Park & switch (online lookup)")
        case "公共交通":
            return tr("公共交通", "Public transit")
        case "驾车直达":
            return tr("驾车直达", "Drive all the way")
        case "步行":
            return tr("步行", "Walk")
        default:
            if detail.hasPrefix("停车换乘（联网："), detail.hasSuffix("）") {
                let source = detail
                    .dropFirst("停车换乘（联网：".count)
                    .dropLast()
                return tr(detail, "Park & switch (online: \(source))")
            }
            if detail.hasPrefix("公共交通｜线路 ") {
                let lines = detail.dropFirst("公共交通｜线路 ".count)
                return tr(detail, "Public transit | \(lines)")
            }
            return detail
        }
    }

    static func == (lhs: PlanSegment, rhs: PlanSegment) -> Bool { lhs.id == rhs.id }
}

/// 一套完整出行方案。
struct CommutePlan: Identifiable, Equatable {
    let id = UUID()
    let mode: CommuteMode
    let segments: [PlanSegment]
    /// 总成本（元）。
    let cost: Double
    /// 门到门总耗时（小时）。
    let durationHours: Double
    /// 总碳排放（kg CO₂）。
    let carbonKg: Double
    var highlight: String?
    let summary: String
    /// 目的地货币代码（如 "CNY"、"USD"），价格按此显示。
    var currencyCode: String = CurrencyFormat.deviceCurrencyCode
    /// 成本是否完整：若停车费联网未查到，则为 false（总价为下限）。
    var costIsComplete: Bool = true
    /// 可在 Apple 地图中发起的真实导航段。
    var navLegs: [NavLeg] = []
    /// 可选的顺风车 / 拼车入口。
    var rideshareURL: URL?
    /// 可选的电车充电 / 充电路线规划入口。
    var electroverseURL: URL?

    /// 用于地图预览的所有路线几何。
    var polylines: [MKPolyline] {
        navLegs.compactMap { $0.polyline }
    }

    var durationText: String {
        DurationFormat.text(hours: durationHours)
    }

    var costText: String {
        let value = CurrencyFormat.string(cost, code: currencyCode)
        // 有未填项时，总价是下限，用「≥」表示，避免误导。
        return costIsComplete ? value : "≥ \(value)"
    }
    var carbonText: String { String(format: "%.1f kg CO₂", carbonKg) }

    static func == (lhs: CommutePlan, rhs: CommutePlan) -> Bool { lhs.id == rhs.id }
}

extension PlanSegment {
    var showsCost: Bool {
        switch mode {
        case .bus, .subway:
            return false
        case .drive, .walk, .park:
            return true
        }
    }

    var durationText: String {
        DurationFormat.text(hours: durationHours, minMinutes: 1)
    }

    var costText: String {
        cost <= 0.01 ? tr("免费", "Free") : CurrencyFormat.string(cost, code: currencyCode)
    }

    var transitTimeText: String {
        guard let departureDate else { return durationText }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return tr("\(durationText) · \(formatter.string(from: departureDate)) 出发",
                  "\(durationText) · departs \(formatter.string(from: departureDate))")
    }
}

/// 时长格式化（本地化）。
enum DurationFormat {
    static func text(hours value: Double, minMinutes: Int = 0) -> String {
        let totalMinutes = max(minMinutes, Int((value * 60).rounded()))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return tr("\(m) 分钟", "\(m) min") }
        if m == 0 { return tr("\(h) 小时", "\(h) h") }
        return tr("\(h) 小时 \(m) 分钟", "\(h) h \(m) min")
    }
}
