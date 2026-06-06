import Foundation

/// 一条出行方案（对应某种出行方式的成本/时间估算结果）。
struct TravelPlan: Identifiable, Equatable {
    let id = UUID()
    let mode: TravelMode
    /// 单人总花费（元）。
    let cost: Double
    /// 门到门总耗时（小时）。
    let durationHours: Double
    /// 舒适度（0~5）。
    let comfortScore: Double
    /// 总碳排放（kg CO₂）。
    let carbonKg: Double
    /// 该方案的亮点标签，如「最快」「最省钱」。
    var highlight: String?
    /// 一句话点评。
    let summary: String

    /// 把小时格式化为「X小时Y分钟」。
    var durationText: String {
        let totalMinutes = Int((durationHours * 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)分钟" }
        if minutes == 0 { return "\(hours)小时" }
        return "\(hours)小时\(minutes)分钟"
    }

    var costText: String {
        "¥\(Int(cost.rounded()))"
    }

    var carbonText: String {
        String(format: "%.1f kg CO₂", carbonKg)
    }

    static func == (lhs: TravelPlan, rhs: TravelPlan) -> Bool {
        lhs.id == rhs.id
    }
}
