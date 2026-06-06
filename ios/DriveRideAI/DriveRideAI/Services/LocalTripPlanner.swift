import Foundation

/// 离线启发式出行规划引擎。
///
/// 流程：
/// 1. 从自然语言解析出发地、目的地、人数、预算、偏好；
/// 2. 估算距离；
/// 3. 为每种合理的出行方式估算成本与时间；
/// 4. 标注亮点（最快 / 最省钱 / 最舒适 / 最环保），并按偏好排序。
struct LocalTripPlanner: TripPlanning {

    func plan(for userText: String) async throws -> TripPlanningResult {
        let request = parse(userText)

        guard let destination = request.destination else {
            return TripPlanningResult(
                request: request,
                plans: [],
                assistantText: "我可以帮你比较不同出行方式的成本和时间。请告诉我你的出发地和目的地，例如：「我想从北京去上海，预算有限，周五出发」。"
            )
        }

        guard let distance = request.distanceKm, distance > 0 else {
            let origin = request.origin ?? "出发地"
            return TripPlanningResult(
                request: request,
                plans: [],
                assistantText: "我识别到目的地是「\(destination)」，但还不能确定从「\(origin)」到这里的距离。可以补充一下出发城市吗？目前我熟悉国内主要城市之间的线路。"
            )
        }

        let plans = makePlans(request: request, distance: distance)
        let text = makeAssistantText(request: request, distance: distance, plans: plans)

        return TripPlanningResult(request: request, plans: plans, assistantText: text)
    }

    // MARK: - 自然语言解析

    func parse(_ text: String) -> TripRequest {
        let cities = RouteData.detectCities(in: text)
        var origin: String?
        var destination: String?

        // 优先用「从 A 到/去 B」结构判断方向。
        if let fromRange = text.range(of: "从") {
            let afterFrom = String(text[fromRange.upperBound...])
            if let firstCity = RouteData.detectCities(in: afterFrom).first {
                origin = firstCity
            }
        }
        for keyword in ["到", "去", "至", "飞往", "前往"] {
            if let range = text.range(of: keyword) {
                let after = String(text[range.upperBound...])
                if let city = RouteData.detectCities(in: after).first {
                    destination = city
                    break
                }
            }
        }

        // 回退：按出现顺序，第一个为出发地，第二个为目的地。
        if destination == nil {
            if cities.count >= 2 {
                origin = origin ?? cities[0]
                destination = cities[1]
            } else if cities.count == 1 {
                destination = cities[0]
            }
        }
        if origin == destination { origin = nil }

        let distance: Double? = {
            if let o = origin, let d = destination {
                return RouteData.estimatedDistance(from: o, to: d)
            }
            return nil
        }()

        return TripRequest(
            origin: origin,
            destination: destination,
            distanceKm: distance,
            preference: detectPreference(text),
            passengers: detectPassengers(text),
            budget: detectBudget(text),
            rawText: text
        )
    }

    private func detectPreference(_ text: String) -> TripPreference {
        let fast = ["快", "尽快", "时间紧", "赶时间", "最快", "急"]
        let cheap = ["省钱", "便宜", "预算有限", "穷游", "经济", "划算", "省"]
        let comfort = ["舒适", "舒服", "轻松", "不累", "商务"]
        let green = ["环保", "低碳", "绿色", "碳排放"]

        if cheap.contains(where: text.contains) { return .cheapest }
        if fast.contains(where: text.contains) { return .fastest }
        if comfort.contains(where: text.contains) { return .comfortable }
        if green.contains(where: text.contains) { return .greenest }
        return .balanced
    }

    private func detectPassengers(_ text: String) -> Int {
        // 匹配「N人 / N个人 / 一家三口」等常见表达。
        if text.contains("一家三口") { return 3 }
        if text.contains("情侣") || text.contains("两个人") || text.contains("二人") { return 2 }

        let pattern = "(\\d+)\\s*(人|位|个人)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let n = Int(text[range]), n > 0, n < 50 {
            return n
        }
        return 1
    }

    private func detectBudget(_ text: String) -> Double? {
        // 匹配「预算 800」「800元以内」「不超过1000」等。
        let pattern = "(\\d{2,6})\\s*(元|块|rmb|RMB)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let budgetKeywords = ["预算", "不超过", "以内", "最多", "块", "元"]
        guard budgetKeywords.contains(where: text.contains) else { return nil }
        for match in matches {
            if let range = Range(match.range(at: 1), in: text),
               let value = Double(text[range]), value >= 50 {
                return value
            }
        }
        return nil
    }

    // MARK: - 方案生成

    private func makePlans(request: TripRequest, distance: Double) -> [TravelPlan] {
        let passengers = max(1, request.passengers)

        var plans: [TravelPlan] = TravelMode.allCases.compactMap { mode in
            guard distance >= mode.minReasonableDistanceKm,
                  distance <= mode.maxReasonableDistanceKm else { return nil }

            let travelHours = distance / mode.averageSpeedKmh
            let durationHours = travelHours + mode.fixedOverheadHours

            // 自驾按车计费（油费/过路费不随人数线性增长），其余按人计费。
            let perPersonCost = distance * mode.costPerKm
            let cost: Double
            switch mode {
            case .driving:
                cost = perPersonCost // 整车成本，与人数无关
            default:
                cost = perPersonCost * Double(passengers)
            }

            let carbon = distance * mode.carbonPerKm * (mode == .driving ? 1 : Double(passengers))

            return TravelPlan(
                mode: mode,
                cost: cost,
                durationHours: durationHours,
                comfortScore: mode.comfortScore,
                carbonKg: carbon,
                highlight: nil,
                summary: summaryFor(mode: mode, distance: distance)
            )
        }

        guard !plans.isEmpty else { return [] }

        annotateHighlights(&plans)
        return sort(plans, by: request.preference)
    }

    private func annotateHighlights(_ plans: inout [TravelPlan]) {
        if let cheapest = plans.min(by: { $0.cost < $1.cost }),
           let idx = plans.firstIndex(of: cheapest) {
            plans[idx].highlight = "最省钱"
        }
        if let fastest = plans.min(by: { $0.durationHours < $1.durationHours }),
           let idx = plans.firstIndex(of: fastest) {
            plans[idx].highlight = plans[idx].highlight.map { "\($0) · 最快" } ?? "最快"
        }
        if let greenest = plans.min(by: { $0.carbonKg < $1.carbonKg }),
           let idx = plans.firstIndex(of: greenest), plans[idx].highlight == nil {
            plans[idx].highlight = "最环保"
        }
        if let comfiest = plans.max(by: { $0.comfortScore < $1.comfortScore }),
           let idx = plans.firstIndex(of: comfiest), plans[idx].highlight == nil {
            plans[idx].highlight = "最舒适"
        }
    }

    private func sort(_ plans: [TravelPlan], by preference: TripPreference) -> [TravelPlan] {
        switch preference {
        case .cheapest:
            return plans.sorted { $0.cost < $1.cost }
        case .fastest:
            return plans.sorted { $0.durationHours < $1.durationHours }
        case .comfortable:
            return plans.sorted { $0.comfortScore > $1.comfortScore }
        case .greenest:
            return plans.sorted { $0.carbonKg < $1.carbonKg }
        case .balanced:
            return plans.sorted { score($0) > score($1) }
        }
    }

    /// 综合评分：成本、时间、舒适度做归一化后加权。
    private func score(_ plan: TravelPlan) -> Double {
        let costScore = 1.0 / (plan.cost + 1)
        let timeScore = 1.0 / (plan.durationHours + 1)
        let comfort = plan.comfortScore / 5.0
        return costScore * 4000 + timeScore * 4 + comfort * 1.5
    }

    private func summaryFor(mode: TravelMode, distance: Double) -> String {
        switch mode {
        case .flight: return "航程快，适合长途；记得预留值机与安检时间。"
        case .highSpeedRail: return "市中心直达、准点率高，中长途性价比之选。"
        case .train: return "票价最低，适合预算紧或夜间卧铺出行。"
        case .driving: return "时间灵活、可多人分摊，适合自由行与带行李。"
        case .coach: return "价格实惠，适合没有高铁直达的中短途。"
        case .rideHailing: return "门到门、省心，适合短途或接驳。"
        }
    }

    private func makeAssistantText(request: TripRequest, distance: Double, plans: [TravelPlan]) -> String {
        let origin = request.origin ?? "你的位置"
        let destination = request.destination ?? "目的地"
        var lines: [String] = []
        lines.append("已为你分析 \(origin) → \(destination)（约 \(Int(distance)) 公里，\(request.passengers) 人，\(request.preference.displayName)）。")

        if let best = plans.first {
            lines.append("综合来看，「\(best.mode.displayName)」最贴合你的需求：\(best.costText)、\(best.durationText)。")
        }
        if let budget = request.budget {
            let within = plans.filter { $0.cost <= budget }
            if within.isEmpty {
                lines.append("注意：在 ¥\(Int(budget)) 预算内暂时没有完全匹配的方案，下面按接近程度排序。")
            } else {
                lines.append("其中 \(within.count) 种方案在你 ¥\(Int(budget)) 的预算内。")
            }
        }
        lines.append("下面是几种可选方案对比 👇")
        return lines.joined(separator: "\n")
    }
}
