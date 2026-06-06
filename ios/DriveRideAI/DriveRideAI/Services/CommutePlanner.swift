import Foundation
import MapKit

/// Agent 的输入。
struct PlanningInput {
    var origin: ResolvedPlace?
    var destination: ResolvedPlace?
    var userText: String
    var profile: UserProfile
}

/// Agent 的输出。
struct PlanningOutcome {
    var assistantText: String
    var plans: [CommutePlan]
    var quickReplies: [String]
    var resolvedOrigin: String?
    var resolvedDestination: String?
}

/// Drive&Ride 规划 Agent —— 使用 MapKit 真实路线。
///
/// 工作流：
/// 1. 取出发地、目的地（真实坐标，来自地址搜索 / 定位）；
/// 2. 用 MKDirections 计算真实的驾车路线与公交 ETA；
/// 3. 搜索真实的 P+R 停车换乘点，组合「驾车 + 公共交通」；
/// 4. 分析描述判断紧急程度；
/// 5. 按真实里程/时长计算成本与时间，给出多套方案（含可发起的导航）。
struct CommutePlanner {

    private let routeService = RouteService()

    private enum Const {
        static let transitSpeedFallback = 22.0   // 公交无 ETA 时的兜底速度 km/h
        static let transitAccessHours = 12.0 / 60.0

        static let cityParkingFee = 30.0         // 市中心停车费估算（元）
        static let prParkingFee = 10.0           // 换乘停车场停车费估算（元）
        static let cityParkingSearchHours = 8.0 / 60.0
        static let prParkSwitchHours = 4.0 / 60.0

        static let carCarbonPerKm = 0.16
        static let evCarbonPerKm = 0.07
        static let transitCarbonPerKm = 0.05

        static let prMinDistanceKm = 6.0         // 低于此距离不建议 P+R
    }

    func plan(_ input: PlanningInput) async -> PlanningOutcome {
        guard let origin = input.origin, let destination = input.destination else {
            return askForLocations(origin: input.origin, destination: input.destination)
        }

        // 真实路线：驾车（含几何）+ 公交 ETA。
        async let drivingTask = routeService.route(from: origin.coordinate,
                                                   to: destination.coordinate,
                                                   transport: .automobile)
        async let transitTask = routeService.transitETA(from: origin.coordinate,
                                                        to: destination.coordinate)
        let driving = await drivingTask
        let transit = await transitTask

        guard driving != nil || transit != nil else {
            return PlanningOutcome(
                assistantText: tr(
                    "我没能在「\(origin.name)」和「\(destination.name)」之间规划出路线，可能距离过远或地址不够准确。可以换一个更具体的地址再试。",
                    "I couldn't find a route between \(origin.name) and \(destination.name) — they may be too far apart or the addresses aren't precise. Try a more specific address."
                ),
                plans: [],
                quickReplies: [],
                resolvedOrigin: origin.name,
                resolvedDestination: destination.name
            )
        }

        let urgency = detectUrgency(input.userText)
        var plans: [CommutePlan] = []

        if let transitPlan = makeTransitPlan(origin: origin, destination: destination,
                                             transit: transit, driving: driving,
                                             profile: input.profile) {
            plans.append(transitPlan)
        }

        if input.profile.hasCar, let driving {
            plans.append(makeCarPlan(origin: origin, destination: destination,
                                     driving: driving, profile: input.profile))

            if driving.distanceKm >= Const.prMinDistanceKm,
               let prPlan = await makeParkRidePlan(origin: origin, destination: destination,
                                                   driving: driving, profile: input.profile) {
                plans.append(prPlan)
            }
        }

        annotateHighlights(&plans)
        plans = sort(plans, urgency: urgency, preference: input.profile.preference)

        let text = composeNarrative(origin: origin, destination: destination,
                                    driving: driving, urgency: urgency,
                                    profile: input.profile, plans: plans)

        return PlanningOutcome(assistantText: text, plans: plans, quickReplies: [],
                               resolvedOrigin: origin.name, resolvedDestination: destination.name)
    }

    // MARK: - 方案构建

    private func makeTransitPlan(origin: ResolvedPlace, destination: ResolvedPlace,
                                 transit: RouteLeg?, driving: RouteLeg?,
                                 profile: UserProfile) -> CommutePlan? {
        let distance: Double
        let hours: Double
        if let transit {
            distance = transit.distanceKm
            hours = transit.travelHours
        } else if let driving {
            distance = driving.distanceKm
            hours = driving.distanceKm / Const.transitSpeedFallback + Const.transitAccessHours
        } else {
            return nil
        }

        let fare = transitFare(km: distance, card: profile.transitCard)
        let segment = PlanSegment(
            mode: .subway,
            detail: transit != nil ? tr("公共交通直达（实时）", "Public transit (live ETA)")
                                    : tr("公共交通直达（估算）", "Public transit (estimated)"),
            distanceKm: distance, durationHours: hours, cost: fare
        )
        let navLeg = NavLeg(label: tr("公共交通导航", "Transit navigation"),
                            source: origin.mapItem, destination: destination.mapItem,
                            transport: .transit, polyline: nil)

        return CommutePlan(
            mode: .transit,
            segments: [segment],
            cost: fare,
            durationHours: hours,
            carbonKg: distance * Const.transitCarbonPerKm,
            highlight: nil,
            summary: profile.transitCard.coversTransitFully
                ? tr("已有月票，公共交通边际成本几乎为 0，最省钱。",
                     "With your monthly pass, transit is nearly free — the cheapest option.")
                : tr("无需停车、不受拥堵影响，性价比高。",
                     "No parking, unaffected by traffic — great value."),
            navLegs: [navLeg]
        )
    }

    private func makeCarPlan(origin: ResolvedPlace, destination: ResolvedPlace,
                             driving: RouteLeg, profile: UserProfile) -> CommutePlan {
        let fuelCost = profile.car.energyCostPerKm * driving.distanceKm
        let segments = [
            PlanSegment(mode: .drive, detail: tr("驾车直达（实时路况）", "Drive all the way (live traffic)"),
                        distanceKm: driving.distanceKm, durationHours: driving.travelHours, cost: fuelCost),
            PlanSegment(mode: .park, detail: tr("市中心停车", "Downtown parking"),
                        distanceKm: 0, durationHours: Const.cityParkingSearchHours, cost: Const.cityParkingFee)
        ]
        let navLeg = NavLeg(label: tr("驾车导航", "Driving navigation"),
                            source: origin.mapItem, destination: destination.mapItem,
                            transport: .automobile, polyline: driving.polyline)

        return CommutePlan(
            mode: .car,
            segments: segments,
            cost: fuelCost + Const.cityParkingFee,
            durationHours: driving.travelHours + Const.cityParkingSearchHours,
            carbonKg: driving.distanceKm * carbonPerKm(for: profile.car),
            highlight: nil,
            summary: tr("门到门最直接，适合赶时间或多人同行；市中心停车费较高。",
                        "Most direct door-to-door; good when rushed or with companions, but downtown parking is pricey."),
            navLegs: [navLeg]
        )
    }

    private func makeParkRidePlan(origin: ResolvedPlace, destination: ResolvedPlace,
                                  driving: RouteLeg, profile: UserProfile) async -> CommutePlan? {
        // 在靠近目的地一侧（约 65% 处）搜索真实换乘停车场。
        let searchPoint = RouteService.interpolate(origin.coordinate, destination.coordinate, fraction: 0.65)
        guard let lot = await routeService.findParkAndRide(near: searchPoint) else { return nil }

        let lotCoord = lot.placemark.coordinate
        // 避免选到离起点太近或就在终点的「停车场」。
        let driveStraight = RouteService.straightLineKm(origin.coordinate, lotCoord)
        let toDestStraight = RouteService.straightLineKm(lotCoord, destination.coordinate)
        guard driveStraight > 1.0, toDestStraight > 0.5 else { return nil }

        async let driveTask = routeService.route(from: origin.coordinate, to: lotCoord, transport: .automobile)
        async let transitTask = routeService.transitETA(from: lotCoord, to: destination.coordinate)
        guard let driveLeg = await driveTask else { return nil }
        let transitLeg = await transitTask

        let transitDistance = transitLeg?.distanceKm ?? toDestStraight * 1.3
        let transitHours = transitLeg?.travelHours
            ?? (transitDistance / Const.transitSpeedFallback + Const.transitAccessHours)
        let fare = transitFare(km: transitDistance, card: profile.transitCard)
        let driveCost = profile.car.energyCostPerKm * driveLeg.distanceKm

        let lotName = lot.name ?? tr("换乘停车场", "Park & Ride lot")
        let segments = [
            PlanSegment(mode: .drive, detail: tr("驾车至「\(lotName)」", "Drive to \(lotName)"),
                        distanceKm: driveLeg.distanceKm, durationHours: driveLeg.travelHours, cost: driveCost),
            PlanSegment(mode: .park, detail: tr("停车换乘（费用估算）", "Park & switch (fee estimated)"),
                        distanceKm: 0, durationHours: Const.prParkSwitchHours, cost: Const.prParkingFee),
            PlanSegment(mode: .subway,
                        detail: transitLeg != nil ? tr("公共交通进城（实时）", "Transit into the city (live)")
                                                  : tr("公共交通进城（估算）", "Transit into the city (estimated)"),
                        distanceKm: transitDistance, durationHours: transitHours, cost: fare)
        ]
        let total = driveCost + Const.prParkingFee + fare
        let time = driveLeg.travelHours + Const.prParkSwitchHours + transitHours
        let carbon = driveLeg.distanceKm * carbonPerKm(for: profile.car) + transitDistance * Const.transitCarbonPerKm

        let navLegs = [
            NavLeg(label: tr("驾车到换乘点", "Drive to lot"),
                   source: origin.mapItem, destination: lot,
                   transport: .automobile, polyline: driveLeg.polyline),
            NavLeg(label: tr("换乘进城", "Transit to destination"),
                   source: lot, destination: destination.mapItem,
                   transport: .transit, polyline: nil)
        ]

        return CommutePlan(
            mode: .parkAndRide,
            segments: segments,
            cost: total,
            durationHours: time,
            carbonKg: carbon,
            highlight: nil,
            summary: tr("在「\(lotName)」停车换乘，避开市区拥堵与高价停车，通勤推荐。",
                        "Park at \(lotName) and switch to transit — skip downtown congestion and pricey parking. Great for commuting."),
            navLegs: navLegs
        )
    }

    // MARK: - 计费

    private func transitFare(km: Double, card: TransitCard) -> Double {
        if card.coversTransitFully { return 0 }
        let base = min(max(2.0, 2.0 + 0.3 * km), 12.0)
        return base * card.fareMultiplier
    }

    private func carbonPerKm(for car: CarProfile) -> Double {
        car.fuelType == .electric ? Const.evCarbonPerKm : Const.carCarbonPerKm
    }

    // MARK: - 紧急程度

    func detectUrgency(_ text: String) -> Urgency {
        let lower = text.lowercased()
        let urgentZh = ["赶时间", "尽快", "快点", "很急", "着急", "来不及", "马上", "迟到", "赶飞机", "赶火车", "赶高铁", "急"]
        let relaxedZh = ["不急", "不赶", "慢慢", "随便", "散步", "悠闲", "时间充裕", "无所谓时间"]
        let urgentEn = ["hurry", "asap", "urgent", "rush", "quick", "fast", "late", "in a hurry", "running late"]
        let relaxedEn = ["no rush", "not in a hurry", "relaxed", "leisure", "take my time", "no hurry"]

        if relaxedZh.contains(where: text.contains) || relaxedEn.contains(where: lower.contains) { return .relaxed }
        if urgentZh.contains(where: text.contains) || urgentEn.contains(where: lower.contains) { return .urgent }
        return .normal
    }

    // MARK: - 排序与高亮

    private func annotateHighlights(_ plans: inout [CommutePlan]) {
        let cheapestTag = tr("最省钱", "Cheapest")
        let fastestTag = tr("最快", "Fastest")
        let greenestTag = tr("最环保", "Greenest")
        if let cheapest = plans.min(by: { $0.cost < $1.cost }),
           let idx = plans.firstIndex(of: cheapest) {
            plans[idx].highlight = cheapestTag
        }
        if let fastest = plans.min(by: { $0.durationHours < $1.durationHours }),
           let idx = plans.firstIndex(of: fastest) {
            plans[idx].highlight = plans[idx].highlight.map { "\($0) · \(fastestTag)" } ?? fastestTag
        }
        if let greenest = plans.min(by: { $0.carbonKg < $1.carbonKg }),
           let idx = plans.firstIndex(of: greenest), plans[idx].highlight == nil {
            plans[idx].highlight = greenestTag
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

    private func score(_ plan: CommutePlan, urgency: Urgency) -> Double {
        let costWeight = urgency == .relaxed ? 5000.0 : 3000.0
        let timeWeight = urgency == .relaxed ? 2.0 : 5.0
        return (1.0 / (plan.cost + 1)) * costWeight + (1.0 / (plan.durationHours + 0.2)) * timeWeight
    }

    // MARK: - 文案

    private func askForLocations(origin: ResolvedPlace?, destination: ResolvedPlace?) -> PlanningOutcome {
        let text: String
        if origin == nil && destination == nil {
            text = tr("请在上方填写出发地和目的地（支持地址搜索，或点定位用当前位置）。",
                      "Please set your origin and destination above (address search supported, or tap locate to use your current position).")
        } else if destination == nil {
            text = tr("出发地已设置。请填写目的地。", "Origin set. Please enter a destination.")
        } else {
            text = tr("目的地已设置。请填写出发地。", "Destination set. Please enter an origin.")
        }
        return PlanningOutcome(assistantText: text, plans: [], quickReplies: [],
                               resolvedOrigin: origin?.name, resolvedDestination: destination?.name)
    }

    private func composeNarrative(origin: ResolvedPlace, destination: ResolvedPlace,
                                  driving: RouteLeg?, urgency: Urgency,
                                  profile: UserProfile, plans: [CommutePlan]) -> String {
        var lines: [String] = []
        if let driving {
            let dist = formatDistance(driving.distanceKm)
            lines.append(tr(
                "已用实时路线分析 \(origin.name) → \(destination.name)（驾车约 \(dist)，\(urgency.displayName)）。",
                "Analyzed \(origin.name) → \(destination.name) with live routing (driving ~\(dist), \(urgency.displayName))."
            ))
        } else {
            lines.append(tr(
                "已分析 \(origin.name) → \(destination.name)（\(urgency.displayName)）。",
                "Analyzed \(origin.name) → \(destination.name) (\(urgency.displayName))."
            ))
        }

        if !profile.hasCar {
            lines.append(tr("你设置为「无车」，仅比较公共交通方案。",
                            "Your profile is \"no car\", so only transit options are compared."))
        }

        if let best = plans.first {
            switch urgency {
            case .urgent:
                lines.append(tr("赶时间，优先推荐最快的「\(best.mode.displayName)」：\(best.costText)、\(best.durationText)。",
                                "In a hurry — fastest is \(best.mode.displayName): \(best.costText), \(best.durationText)."))
            case .relaxed:
                lines.append(tr("不赶时间，优先推荐更省钱的「\(best.mode.displayName)」：\(best.costText)、\(best.durationText)。",
                                "Not rushed — cheaper option is \(best.mode.displayName): \(best.costText), \(best.durationText)."))
            case .normal:
                lines.append(tr("综合成本与时间，推荐「\(best.mode.displayName)」：\(best.costText)、\(best.durationText)。",
                                "Balancing cost and time, I recommend \(best.mode.displayName): \(best.costText), \(best.durationText)."))
            }
        }
        lines.append(tr("点方案里的「导航」可直接用 Apple 地图出发 👇", "Tap \"Navigate\" in a plan to start in Apple Maps 👇"))
        return lines.joined(separator: "\n")
    }

    private func formatDistance(_ km: Double) -> String {
        km >= 10
            ? tr("\(Int(km.rounded())) 公里", "\(Int(km.rounded())) km")
            : tr(String(format: "%.1f 公里", km), String(format: "%.1f km", km))
    }
}
