import Foundation

/// 规划结果：包含解析出的需求、生成的方案，以及给用户的文字说明。
struct TripPlanningResult {
    let request: TripRequest
    let plans: [TravelPlan]
    let assistantText: String
}

/// 出行规划服务协议。
///
/// 默认实现为离线启发式引擎 `LocalTripPlanner`；
/// 也可以实现一个调用大语言模型 / 真实票价 API 的版本（见 `AITripPlanner`）。
protocol TripPlanning {
    func plan(for userText: String) async throws -> TripPlanningResult
}
