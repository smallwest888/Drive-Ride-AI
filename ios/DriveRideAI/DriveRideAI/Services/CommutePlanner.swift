import Foundation

/// Agent 的输入。
struct PlanningInput {
    var origin: TripLocation?
    var destination: TripLocation?
    var userText: String
    var profile: UserProfile
}

/// Agent 的输出。
struct PlanningOutcome {
    var assistantText: String
    var plans: [CommutePlan]
    /// 信息不足时给出的快捷追问选项。
    var quickReplies: [String]
    /// Agent 解析出的起终点（用于回填界面）。
    var resolvedOrigin: String?
    var resolvedDestination: String?
}

/// Drive&Ride 规划 Agent。
///
/// 工作流：
/// 1. 获取出发地、目的地（界面字段优先，其次从描述中抽取）；
/// 2. 确定行程距离（描述中的显式距离优先，其次按已知城市估算）；
/// 3. 分析描述判断紧急程度；
/// 4. 判断可行方式：公交 / 自驾 / P+R 换乘（依据是否有车）；
/// 5. 计算每种方式的总成本与总时间，给出多套方案；
/// 6. 信息不足时主动追问。
struct CommutePlanner {

    // MARK: - 估算参数
    private enum Const {
        static let cityDriveSpeed = 26.0      // 市区平均车速 km/h（含拥堵）
        static let suburbDriveSpeed = 52.0    // 城郊/快速路车速 km/h
        static let transitSpeed = 22.0        // 公共交通有效速度 km/h（含停站）
        static let walkSpeed = 4.6            // 步行 km/h

        static let cityParkingFee = 30.0      // 市中心停车费（元，估算）
        static let cityParkingSearchHours = 10.0 / 60.0  // 找车位/步行 10 分钟
        static let prParkSwitchHours = 4.0 / 60.0        // 换乘 4 分钟

        static let transitAccessHours = 12.0 / 60.0 // 公交首末步行+候车 ~12 分钟

        static let carCarbonPerKm = 0.16      // kg CO₂/km（燃油车近似）
        static let evCarbonPerKm = 0.07       // kg CO₂/km（纯电近似）
        static let transitCarbonPerKm = 0.05  // kg CO₂/km
    }

    func plan(_ input: PlanningInput) -> PlanningOutcome {
        let resolved = resolveItinerary(input)

        // 缺少目的地（或出发地）→ 主动追问。
        guard let originName = resolved.origin, let destName = resolved.destination else {
            return askForLocations(resolved: resolved)
        }

        // 距离无法确定 → 主动追问。
        guard let distance = resolved.distanceKm, distance > 0 else {
            return PlanningOutcome(
                assistantText: "我已记录行程：\(originName) → \(destName)。不过我还不能确定这两地之间的大致距离，方便告诉我吗？也可以直接在描述里写「约 15 公里」。",
                plans: [],
                quickReplies: ["约 5 公里", "约 15 公里", "约 30 公里", "约 50 公里"],
                resolvedOrigin: originName,
                resolvedDestination: destName
            )
        }

        let urgency = detectUrgency(input.userText)
        let plans = buildPlans(distance: distance, profile: input.profile, urgency: urgency)

        let text = composeNarrative(
            origin: originName,
            destination: destName,
            distance: distance,
            urgency: urgency,
            profile: input.profile,
            plans: plans
        )

        return PlanningOutcome(
            assistantText: text,
            plans: plans,
            quickReplies: [],
            resolvedOrigin: originName,
            resolvedDestination: destName
        )
    }

    // MARK: - 行程解析

    private struct ResolvedItinerary {
        var origin: String?
        var destination: String?
        var distanceKm: Double?
    }

    private func resolveItinerary(_ input: PlanningInput) -> ResolvedItinerary {
        var origin = input.origin.flatMap { $0.isEmpty ? nil : $0.name }
        var destination = input.destination.flatMap { $0.isEmpty ? nil : $0.name }

        // 字段为空时，尝试从描述中抽取城市（「从 A 到 B」结构优先）。
        if origin == nil || destination == nil {
            let extracted = extractEndpoints(from: input.userText)
            origin = origin ?? extracted.origin
            destination = destination ?? extracted.destination
        }

        // 距离：显式数字优先，其次按已知城市估算。
        var distance = explicitDistance(in: input.userText)
        if distance == nil, let o = origin, let d = destination {
            distance = RouteData.estimatedDistance(from: o, to: d)
        }

        return ResolvedItinerary(origin: origin, destination: destination, distanceKm: distance)
    }

    private func extractEndpoints(from text: String) -> (origin: String?, destination: String?) {
        var origin: String?
        var destination: String?

        if let fromRange = text.range(of: "从") {
            let after = String(text[fromRange.upperBound...])
            origin = RouteData.detectCities(in: after).first
        }
        for keyword in ["到", "去", "至", "前往"] {
            if let range = text.range(of: keyword) {
                let after = String(text[range.upperBound...])
                if let city = RouteData.detectCities(in: after).first {
                    destination = city
                    break
                }
            }
        }

        if destination == nil {
            let cities = RouteData.detectCities(in: text)
            if cities.count >= 2 {
                origin = origin ?? cities[0]
                destination = cities[1]
            } else if cities.count == 1 {
                destination = cities[0]
            }
        }
        if origin == destination { origin = nil }
        return (origin, destination)
    }

    private func explicitDistance(in text: String) -> Double? {
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*(公里|千米|km|KM|Km|km)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text),
              let value = Double(text[r]), value > 0 else { return nil }
        return value
    }

    // MARK: - 紧急程度分析

    func detectUrgency(_ text: String) -> Urgency {
        let urgent = ["赶时间", "尽快", "快点", "很急", "着急", "来不及", "马上", "迟到", "赶飞机", "赶火车", "赶高铁", "急"]
        let relaxed = ["不急", "不赶", "慢慢", "随便", "散步", "悠闲", "时间充裕", "无所谓时间"]
        if relaxed.contains(where: text.contains) { return .relaxed }
        if urgent.contains(where: text.contains) { return .urgent }
        return .normal
    }

    // MARK: - 方案构建

    private func buildPlans(distance: Double, profile: UserProfile, urgency: Urgency) -> [CommutePlan] {
        var plans: [CommutePlan] = [makeTransitPlan(distance: distance, profile: profile)]

        if profile.hasCar {
            plans.append(makeCarPlan(distance: distance, profile: profile))
            if distance >= ParkRideData.minApplicableDistanceKm {
                plans.append(makeParkRidePlan(distance: distance, profile: profile))
            }
        }

        annotateHighlights(&plans)
        return sort(plans, urgency: urgency, preference: profile.preference)
    }

    // 全程公交
    private func makeTransitPlan(distance: Double, profile: UserProfile) -> CommutePlan {
        let walkKm = 0.6
        let rideKm = max(0, distance - walkKm)
        let rideHours = rideKm / Const.transitSpeed + Const.transitAccessHours
        let walkHours = walkKm / Const.walkSpeed
        let fare = transitFare(km: rideKm, card: profile.transitCard)

        let segments = [
            PlanSegment(mode: .walk, detail: "步行至车站", distanceKm: walkKm, durationHours: walkHours, cost: 0),
            PlanSegment(mode: .subway, detail: "公共交通直达", distanceKm: rideKm, durationHours: rideHours, cost: fare)
        ]
        let total = segments.reduce(0) { $0 + $1.cost }
        let time = segments.reduce(0) { $0 + $1.durationHours }
        let carbon = rideKm * Const.transitCarbonPerKm

        return CommutePlan(
            mode: .transit,
            segments: segments,
            cost: total,
            durationHours: time,
            carbonKg: carbon,
            highlight: nil,
            summary: profile.transitCard.coversTransitFully
                ? "已有月票，公共交通边际成本几乎为 0，最省钱。"
                : "无需停车、不受拥堵影响，性价比高。"
        )
    }

    // 全程自驾
    private func makeCarPlan(distance: Double, profile: UserProfile) -> CommutePlan {
        let driveHours = distance / Const.cityDriveSpeed + Const.cityParkingSearchHours
        let fuelCost = profile.car.energyCostPerKm * distance
        let parking = Const.cityParkingFee

        let segments = [
            PlanSegment(mode: .drive, detail: "驾车直达（市区路况）", distanceKm: distance,
                        durationHours: distance / Const.cityDriveSpeed, cost: fuelCost),
            PlanSegment(mode: .park, detail: "市中心停车", distanceKm: 0,
                        durationHours: Const.cityParkingSearchHours, cost: parking)
        ]
        let total = fuelCost + parking
        let carbon = distance * carbonPerKm(for: profile.car)

        return CommutePlan(
            mode: .car,
            segments: segments,
            cost: total,
            durationHours: driveHours,
            carbonKg: carbon,
            highlight: nil,
            summary: "门到门最直接，适合赶时间或多人同行；市中心停车费较高。"
        )
    }

    // P+R 换乘：驾车至城郊停车场 + 公共交通进城
    private func makeParkRidePlan(distance: Double, profile: UserProfile) -> CommutePlan {
        let cityLegKm = min(distance * 0.4, 12)      // 拥堵的进城段交给公共交通
        let driveLegKm = max(0, distance - cityLegKm)
        let lot = ParkRideData.selectLot(for: distance)

        let driveHours = driveLegKm / Const.suburbDriveSpeed
        let driveCost = profile.car.energyCostPerKm * driveLegKm

        let transitHours = cityLegKm / Const.transitSpeed + Const.transitAccessHours
        let fare = transitFare(km: cityLegKm, card: profile.transitCard)

        let segments = [
            PlanSegment(mode: .drive, detail: "驾车至「\(lot.name)」", distanceKm: driveLegKm,
                        durationHours: driveHours, cost: driveCost),
            PlanSegment(mode: .park, detail: "停车换乘（\(lot.transitLine)）", distanceKm: 0,
                        durationHours: Const.prParkSwitchHours, cost: lot.parkingFee),
            PlanSegment(mode: .subway, detail: "公共交通进城", distanceKm: cityLegKm,
                        durationHours: transitHours, cost: fare)
        ]
        let total = segments.reduce(0) { $0 + $1.cost }
        let time = segments.reduce(0) { $0 + $1.durationHours }
        let carbon = driveLegKm * carbonPerKm(for: profile.car) + cityLegKm * Const.transitCarbonPerKm

        return CommutePlan(
            mode: .parkAndRide,
            segments: segments,
            cost: total,
            durationHours: time,
            carbonKg: carbon,
            highlight: nil,
            summary: "避开市区拥堵与高价停车，兼顾自驾灵活与公交高效，通勤推荐。"
        )
    }

    // MARK: - 计费与排序

    /// 公共交通票价（元）。
    private func transitFare(km: Double, card: TransitCard) -> Double {
        if card.coversTransitFully { return 0 }
        let base = min(max(2.0, 2.0 + 0.3 * km), 12.0)
        return base * card.fareMultiplier
    }

    private func carbonPerKm(for car: CarProfile) -> Double {
        car.fuelType == .electric ? Const.evCarbonPerKm : Const.carCarbonPerKm
    }

    private func annotateHighlights(_ plans: inout [CommutePlan]) {
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
    }

    private func sort(_ plans: [CommutePlan], urgency: Urgency, preference: CommutePreference) -> [CommutePlan] {
        if urgency == .urgent {
            return plans.sorted { $0.durationHours < $1.durationHours }
        }
        switch preference {
        case .cheapest: return plans.sorted { $0.cost < $1.cost }
        case .fastest:  return plans.sorted { $0.durationHours < $1.durationHours }
        case .greenest: return plans.sorted { $0.carbonKg < $1.carbonKg }
        case .balanced: return plans.sorted { score($0, urgency: urgency) > score($1, urgency: urgency) }
        }
    }

    /// 综合评分：成本与时间归一化加权；不赶时间时更看重成本。
    private func score(_ plan: CommutePlan, urgency: Urgency) -> Double {
        let costWeight = urgency == .relaxed ? 5000.0 : 3000.0
        let timeWeight = urgency == .relaxed ? 2.0 : 5.0
        let costScore = 1.0 / (plan.cost + 1)
        let timeScore = 1.0 / (plan.durationHours + 0.2)
        return costScore * costWeight + timeScore * timeWeight
    }

    // MARK: - 文案

    private func askForLocations(resolved: ResolvedItinerary) -> PlanningOutcome {
        let text: String
        if resolved.origin == nil && resolved.destination == nil {
            text = "好的，我来帮你规划。请告诉我出发地和目的地——可以在上方两个输入框填写，或直接告诉我，比如「从家到公司，大概 20 公里，有点赶」。"
        } else if resolved.destination == nil {
            text = "出发地我记下了（\(resolved.origin ?? "")）。你想去哪儿呢？"
        } else {
            text = "目的地我记下了（\(resolved.destination ?? "")）。从哪里出发呢？"
        }
        return PlanningOutcome(
            assistantText: text,
            plans: [],
            quickReplies: [],
            resolvedOrigin: resolved.origin,
            resolvedDestination: resolved.destination
        )
    }

    private func composeNarrative(origin: String,
                                  destination: String,
                                  distance: Double,
                                  urgency: Urgency,
                                  profile: UserProfile,
                                  plans: [CommutePlan]) -> String {
        var lines: [String] = []
        lines.append("已分析 \(origin) → \(destination)（约 \(formatDistance(distance))，\(urgency.displayName)）。")

        if !profile.hasCar {
            lines.append("你当前设置为「无车」，因此只比较公共交通方案。")
        }

        if let best = plans.first {
            let reason: String
            switch urgency {
            case .urgent: reason = "你比较赶时间，优先推荐用时最短的"
            case .relaxed: reason = "你不赶时间，优先推荐更省钱的"
            case .normal: reason = "综合成本与时间，推荐"
            }
            lines.append("\(reason)「\(best.mode.displayName)」：\(best.costText)、\(best.durationText)。")
        }
        lines.append("下面是几种方案对比 👇")
        return lines.joined(separator: "\n")
    }

    private func formatDistance(_ km: Double) -> String {
        km >= 10 ? "\(Int(km.rounded())) 公里" : String(format: "%.1f 公里", km)
    }
}
