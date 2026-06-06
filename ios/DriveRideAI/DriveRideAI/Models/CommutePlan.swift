import SwiftUI

/// 行程紧急程度，由 Agent 从用户描述中分析得出。
enum Urgency: String, Codable {
    case relaxed   // 不赶时间
    case normal    // 正常
    case urgent    // 很赶

    var displayName: String {
        switch self {
        case .relaxed: return "不赶时间"
        case .normal: return "正常"
        case .urgent: return "时间紧迫"
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
        case .transit: return "全程公交"
        case .car: return "全程自驾"
        case .parkAndRide: return "P+R 换乘"
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
        case .drive: return "驾车"
        case .bus: return "公交"
        case .subway: return "地铁"
        case .walk: return "步行"
        case .park: return "停车换乘"
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

    var durationText: String {
        let totalMinutes = Int((durationHours * 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) 分钟" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    var costText: String { "¥\(Int(cost.rounded()))" }
    var carbonText: String { String(format: "%.1f kg CO₂", carbonKg) }

    static func == (lhs: CommutePlan, rhs: CommutePlan) -> Bool { lhs.id == rhs.id }
}

extension PlanSegment {
    var durationText: String {
        let totalMinutes = max(1, Int((durationHours * 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) 分钟" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    var costText: String {
        cost <= 0.01 ? "免费" : "¥\(Int(cost.rounded()))"
    }
}
