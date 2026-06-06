import Foundation
import MapKit

/// Agent 的输入。
struct PlanningInput {
    var origin: ResolvedPlace?
    var destination: ResolvedPlace?
    var userText: String
    var profile: UserProfile
    /// 本地数据库中的真实 P+R 停车场（优先于 MapKit 搜索）。
    var parkRideLots: [ParkRideLotInfo] = []
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
    /// 后台 AI（可选，OpenAI / Qwen），仅用于润色文案。
    private let ai = AIService()
    /// 价格来源：优先联网 / API（方案 B，预留），取不到回落到用户填写的真实价格（方案 A）。
    private let pricing: PricingProvider = ChainedPricingProvider(
        primary: RemotePricingProvider(),
        fallback: ProfilePricingProvider()
    )

    private enum Const {
        static let transitSpeedFallback = 22.0   // 公交无 ETA 时的兜底速度 km/h
        static let transitAccessHours = 12.0 / 60.0

        // 时间缓冲（找车位 / 换乘步行），非价格。
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
        // 价格按目的地所在地区的货币显示。
        let currency = CurrencyFormat.currencyCode(forCountry: destination.countryCode)
        var plans: [CommutePlan] = []

        if let transitPlan = await makeTransitPlan(origin: origin, destination: destination,
                                                   transit: transit, driving: driving,
                                                   profile: input.profile, currency: currency) {
            plans.append(transitPlan)
        }

        if input.profile.hasCar, let driving {
            plans.append(await makeCarPlan(origin: origin, destination: destination,
                                           driving: driving, profile: input.profile, currency: currency))

            if driving.distanceKm >= Const.prMinDistanceKm,
               let prPlan = await makeParkRidePlan(origin: origin, destination: destination,
                                                   driving: driving, profile: input.profile,
                                                   currency: currency, dbLots: input.parkRideLots) {
                plans.append(prPlan)
            }
        }

        annotateHighlights(&plans)
        plans = sort(plans, urgency: urgency, preference: input.profile.preference)

        var text = composeNarrative(origin: origin, destination: destination,
                                    driving: driving, urgency: urgency,
                                    profile: input.profile, plans: plans)

        // 可选：后台 AI 仅润色文案（保留全部真实数字），未启用 / 失败则用本地文案。
        if let aiSettings = input.profile.ai, aiSettings.isUsable,
           let polished = await ai.polish(text: text, lang: AppLocale.shared.lang, settings: aiSettings) {
            text = polished
        }

        return PlanningOutcome(assistantText: text, plans: plans, quickReplies: [],
                               resolvedOrigin: origin.name, resolvedDestination: destination.name)
    }

    // MARK: - 方案构建

    private func makeTransitPlan(origin: ResolvedPlace, destination: ResolvedPlace,
                                 transit: RouteLeg?, driving: RouteLeg?,
                                 profile: UserProfile, currency: String) async -> CommutePlan? {
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

        let fareQuote = await pricing.transitFare(distanceKm: distance, profile: profile)
        let fare = fareQuote.amount ?? 0
        let liveTag = transit != nil ? tr("实时", "live ETA") : tr("估算", "estimated")
        let detail = fareQuote.isKnown
            ? tr("公共交通直达（\(liveTag)）", "Public transit (\(liveTag))")
            : tr("公共交通直达（\(liveTag)，票价未填）", "Public transit (\(liveTag), fare not set)")
        let segment = PlanSegment(mode: .subway, detail: detail,
                                  distanceKm: distance, durationHours: hours, cost: fare,
                                  currencyCode: currency)
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
            currencyCode: currency,
            costIsComplete: fareQuote.isKnown,
            navLegs: [navLeg]
        )
    }

    private func makeCarPlan(origin: ResolvedPlace, destination: ResolvedPlace,
                             driving: RouteLeg, profile: UserProfile, currency: String) async -> CommutePlan {
        let fuelCost = profile.car.energyCostPerKm * driving.distanceKm
        let parkQuote = await pricing.cityParkingFee(near: destination.coordinate, profile: profile)
        let parkFee = parkQuote.amount ?? 0
        let parkDetail = parkQuote.isKnown
            ? tr("市中心停车", "Downtown parking")
            : tr("市中心停车（费用未填）", "Downtown parking (fee not set)")
        let segments = [
            PlanSegment(mode: .drive, detail: tr("驾车直达（实时路况）", "Drive all the way (live traffic)"),
                        distanceKm: driving.distanceKm, durationHours: driving.travelHours, cost: fuelCost,
                        currencyCode: currency),
            PlanSegment(mode: .park, detail: parkDetail,
                        distanceKm: 0, durationHours: Const.cityParkingSearchHours, cost: parkFee,
                        currencyCode: currency)
        ]
        let navLeg = NavLeg(label: tr("驾车导航", "Driving navigation"),
                            source: origin.mapItem, destination: destination.mapItem,
                            transport: .automobile, polyline: driving.polyline)

        return CommutePlan(
            mode: .car,
            segments: segments,
            cost: fuelCost + parkFee,
            durationHours: driving.travelHours + Const.cityParkingSearchHours,
            carbonKg: driving.distanceKm * carbonPerKm(for: profile.car),
            highlight: nil,
            summary: tr("门到门最直接，适合赶时间或多人同行；市中心停车费较高。",
                        "Most direct door-to-door; good when rushed or with companions, but downtown parking is pricey."),
            currencyCode: currency,
            costIsComplete: parkQuote.isKnown,
            navLegs: [navLeg]
        )
    }

    /// 经 Apple Maps API 验证后的 P+R 候选结果。
    private struct EvaluatedPR {
        let lot: MKMapItem
        /// 若来自本地数据库，则带有真实停车场信息（线路 / 价格 / 车位）。
        let info: ParkRideLotInfo?
        let driveLeg: RouteLeg
        let transitLeg: RouteLeg?
        let transitDistanceKm: Double
        let transitHours: Double
        /// 真实总时间（小时）= 驾车到停车场 + 停车换乘 + 公交到目的地。
        let totalHours: Double
    }

    private func makeParkRidePlan(origin: ResolvedPlace, destination: ResolvedPlace,
                                  driving: RouteLeg, profile: UserProfile, currency: String,
                                  dbLots: [ParkRideLotInfo]) async -> CommutePlan? {
        // 1) 候选停车场：优先用本地数据库里目的地附近的真实 P+R 停车场；
        //    数据库没有覆盖该地区时，回落到 MapKit 搜索。
        let searchPoint = RouteService.interpolate(origin.coordinate, destination.coordinate, fraction: 0.65)
        let nearbyDB = dbLots
            .filter { RouteService.straightLineKm($0.coordinate, destination.coordinate) <= 30 }

        var infoByItem: [ObjectIdentifier: ParkRideLotInfo] = [:]
        let lotItems: [MKMapItem]
        if !nearbyDB.isEmpty {
            lotItems = nearbyDB.map { info in
                let item = MKMapItem(placemark: MKPlacemark(coordinate: info.coordinate))
                item.name = info.name
                infoByItem[ObjectIdentifier(item)] = info
                return item
            }
        } else {
            lotItems = await routeService.searchParkAndRideLots(near: searchPoint)
        }
        guard !lotItems.isEmpty else { return nil }

        // 2) 对所有停车场做本地快速预估（不调用 API），按预估总时间排序。
        let ranked = TimeEstimationManager.rankedCandidates(origin: origin.coordinate,
                                                            destination: destination.coordinate,
                                                            lots: lotItems)

        // 3) 只取预估最优的前 5 个，调 Apple Maps API 做真实路径验证。
        let candidates = Array(ranked.prefix(5))

        // 4) 对前 5 个用真实路线计算「驾车到停车场 + 公交到目的地」并取总时间最优者。
        var best: EvaluatedPR?
        for candidate in candidates {
            let lotCoord = candidate.lot.placemark.coordinate
            // 避免选到离起点太近或就在终点的「停车场」。
            let driveStraight = RouteService.straightLineKm(origin.coordinate, lotCoord)
            let toDestStraight = RouteService.straightLineKm(lotCoord, destination.coordinate)
            guard driveStraight > 1.0, toDestStraight > 0.5 else { continue }

            async let driveTask = routeService.route(from: origin.coordinate, to: lotCoord, transport: .automobile)
            async let transitTask = routeService.transitETA(from: lotCoord, to: destination.coordinate)
            guard let driveLeg = await driveTask else { continue }
            let transitLeg = await transitTask

            let transitDistance = transitLeg?.distanceKm ?? toDestStraight * 1.3
            let transitHours = transitLeg?.travelHours
                ?? (transitDistance / Const.transitSpeedFallback + Const.transitAccessHours)
            let totalHours = driveLeg.travelHours + Const.prParkSwitchHours + transitHours

            let evaluated = EvaluatedPR(lot: candidate.lot,
                                        info: infoByItem[ObjectIdentifier(candidate.lot)],
                                        driveLeg: driveLeg, transitLeg: transitLeg,
                                        transitDistanceKm: transitDistance, transitHours: transitHours,
                                        totalHours: totalHours)
            if best == nil || evaluated.totalHours < best!.totalHours {
                best = evaluated
            }
        }

        guard let pick = best else { return nil }

        let lot = pick.lot
        let info = pick.info
        let driveLeg = pick.driveLeg
        let transitLeg = pick.transitLeg
        let transitDistance = pick.transitDistanceKm
        let transitHours = pick.transitHours
        let driveCost = profile.car.energyCostPerKm * driveLeg.distanceKm

        let fareQuote = await pricing.transitFare(distanceKm: transitDistance, profile: profile)
        let parkQuote = await pricing.parkRideParkingFee(lot: lot, profile: profile)
        let fare = fareQuote.amount ?? 0
        let parkFee = parkQuote.amount ?? 0
        let costComplete = fareQuote.isKnown && parkQuote.isKnown

        let lotName = info?.name ?? lot.name ?? tr("换乘停车场", "Park & Ride lot")
        let liveTag = transitLeg != nil ? tr("实时", "live") : tr("估算", "estimated")

        // 停车费说明：用户填了一口价则用之；否则若数据库有每小时价，展示真实费率（时长不定，不计入总价）。
        var parkDetail: String
        if parkQuote.isKnown {
            parkDetail = tr("停车换乘", "Park & switch")
        } else if let rate = info?.pricePerHour, rate > 0 {
            let rateText = CurrencyFormat.string(rate, code: currency)
            parkDetail = tr("停车换乘（约 \(rateText)/小时，时长不定未计入）",
                            "Park & switch (~\(rateText)/h, duration unknown, excluded)")
        } else {
            parkDetail = tr("停车换乘（费用未填）", "Park & switch (fee not set)")
        }

        // 公交段说明：附上数据库里的真实换乘线路。
        let lines = (info?.publicTransport ?? "").trimmingCharacters(in: .whitespaces)
        var transitDetail = fareQuote.isKnown
            ? tr("公共交通进城（\(liveTag)）", "Transit into the city (\(liveTag))")
            : tr("公共交通进城（\(liveTag)，票价未填）", "Transit into the city (\(liveTag), fare not set)")
        if !lines.isEmpty {
            transitDetail += tr("｜线路 \(lines)", " | \(lines)")
        }
        let segments = [
            PlanSegment(mode: .drive, detail: tr("驾车至「\(lotName)」", "Drive to \(lotName)"),
                        distanceKm: driveLeg.distanceKm, durationHours: driveLeg.travelHours, cost: driveCost,
                        currencyCode: currency),
            PlanSegment(mode: .park, detail: parkDetail,
                        distanceKm: 0, durationHours: Const.prParkSwitchHours, cost: parkFee,
                        currencyCode: currency),
            PlanSegment(mode: .subway, detail: transitDetail,
                        distanceKm: transitDistance, durationHours: transitHours, cost: fare,
                        currencyCode: currency)
        ]
        let total = driveCost + parkFee + fare
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

        var summary = tr("在「\(lotName)」停车换乘，避开市区拥堵与高价停车，通勤推荐。",
                         "Park at \(lotName) and switch to transit — skip downtown congestion and pricey parking. Great for commuting.")
        if let info {
            if info.totalSpaces > 0 {
                summary += tr("（约 \(info.totalSpaces) 个车位）", " (~\(info.totalSpaces) spaces)")
            }
            let note = info.notes.trimmingCharacters(in: .whitespaces)
            if !note.isEmpty { summary += tr("｜提示：\(note)", " | Note: \(note)") }
        }

        return CommutePlan(
            mode: .parkAndRide,
            segments: segments,
            cost: total,
            durationHours: time,
            carbonKg: carbon,
            highlight: nil,
            summary: summary,
            currencyCode: currency,
            costIsComplete: costComplete,
            navLegs: navLegs
        )
    }

    // MARK: - 计费

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
        if plans.contains(where: { !$0.costIsComplete }) {
            lines.append(tr(
                "注：苹果不提供公交票价 / 停车费，标「未填」的项未计入总价（显示为「≥」）。在设置里填上你所在城市的真实价格即可精确计算。",
                "Note: Apple doesn't provide transit fares/parking fees. Items marked \"not set\" are excluded (shown as \"≥\"). Enter your city's real prices in Settings for exact totals."
            ))
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
