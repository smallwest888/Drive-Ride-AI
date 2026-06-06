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
        static let prMaxDistanceToDestinationKm = 20.0
        static let prMinRemainingDistanceKm = 1.0
    }

    private enum ModeIntent: Equatable {
        case any
        case driving
        case transit
        case parkRide

        var displayNameZh: String {
            switch self {
            case .any: return "未指定"
            case .driving: return "优先开车"
            case .transit: return "优先公共交通"
            case .parkRide: return "优先 P+R 换乘"
            }
        }

        var displayNameEn: String {
            switch self {
            case .any: return "not specified"
            case .driving: return "prefer driving"
            case .transit: return "prefer public transit"
            case .parkRide: return "prefer Park & Ride"
            }
        }
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
        let lang = AppLocale.shared.lang
        let aiSettings = input.profile.ai
        async let carCarbonTask = carCarbonEstimateIfNeeded(profile: input.profile,
                                                            lang: lang,
                                                            settings: aiSettings)
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
        let modeIntent = detectModeIntent(input.userText)
        // 价格按目的地所在地区的货币显示。
        let currency = CurrencyFormat.currencyCode(forCountry: destination.countryCode)
        let adacCarbon = await carCarbonTask
        var plans: [CommutePlan] = []
        var searchEvidence: [String] = []
        if let note = adacCarbon.note {
            searchEvidence.append(note)
        }

        if let transitPlan = await makeTransitPlan(origin: origin, destination: destination,
                                                   transit: transit, driving: driving,
                                                   profile: input.profile, currency: currency) {
            plans.append(transitPlan)
        }

        if input.profile.hasCar, let driving {
            let carBuild = await makeCarPlan(origin: origin, destination: destination,
                                             driving: driving, profile: input.profile, currency: currency,
                                             carCarbonKgPerKm: adacCarbon.kgCO2PerKm,
                                             carbonSourceNote: adacCarbon.note,
                                             lang: lang,
                                             aiSettings: aiSettings)
            plans.append(carBuild.plan)
            searchEvidence.append(contentsOf: carBuild.searchEvidence)

            if driving.distanceKm >= Const.prMinDistanceKm,
               let prPlan = await makeParkRidePlan(origin: origin, destination: destination,
                                                   driving: driving, profile: input.profile,
                                                   currency: currency, dbLots: input.parkRideLots,
                                                   carCarbonKgPerKm: adacCarbon.kgCO2PerKm,
                                                   carbonSourceNote: adacCarbon.note,
                                                   lang: lang,
                                                   aiSettings: aiSettings) {
                plans.append(prPlan.plan)
                searchEvidence.append(contentsOf: prPlan.searchEvidence)
            }
        }

        plans = filter(plans, for: modeIntent)
        annotateHighlights(&plans)

        // AI 决策（核心）：在已用真实数据算好的候选中，由 AI 权衡选出最佳并排序、给出理由。
        // AI 只能选择 / 排序 / 解释，不改数字。未启用 / 失败时回落到本地启发式排序。
        var aiReason: String?
        let railFarePremise: String?
        if let aiSettings, aiSettings.isUsable,
           plans.contains(where: { $0.mode == .transit }),
           shouldLookupRailFare(transit: transit, driving: driving) {
            let estimate = await ai.railFareLookupOnDB(
                originText: origin.name,
                destinationText: destination.name,
                routeText: planSummaries(plans, lang: lang).joined(separator: "\n"),
                lang: lang,
                settings: aiSettings
            )
            let evidence = estimate?.evidenceSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            railFarePremise = evidence?.isEmpty == false ? evidence : nil
            if let railFarePremise {
                searchEvidence.append(tr("DB 火车票价：\(railFarePremise)",
                                         "DB rail fare: \(railFarePremise)"))
            } else {
                searchEvidence.append(tr("DB 火车票价：已尝试搜索 DB 官方页面，但未提取到明确票价。",
                                         "DB rail fare: searched DB official pages, but no clear fare was extracted."))
            }
        } else {
            railFarePremise = nil
        }

        let coveragePremise: String?
        if let aiSettings, aiSettings.isUsable, input.profile.transitCard != .none {
            coveragePremise = await ai.transitTicketCoveragePremise(
                originText: origin.name,
                destinationText: destination.name,
                ticketName: input.profile.transitCard.displayName,
                routeText: planSummaries(plans, lang: lang).joined(separator: "\n"),
                lang: lang,
                settings: aiSettings
            )
            if let coverage = coveragePremise?.trimmingCharacters(in: .whitespacesAndNewlines), !coverage.isEmpty {
                searchEvidence.append(tr("德国票种适用范围：\(coverage)",
                                         "German ticket coverage: \(coverage)"))
            }
        } else {
            coveragePremise = nil
            if input.profile.transitCard != .none {
                searchEvidence.append(tr("德国票种适用范围：未搜索（后台 AI 未开启或未配置）。",
                                         "German ticket coverage: not searched (Background AI is off or not configured)."))
            }
        }

        if let aiSettings, aiSettings.isUsable, plans.count > 1,
           let decision = await ai.decideBestPlan(
                candidates: planSummaries(plans, lang: lang),
                context: decisionContext(origin: origin, destination: destination,
                                         driving: driving, urgency: urgency,
                                         profile: input.profile, userText: input.userText,
                                         modeIntent: modeIntent,
                                         ticketCoveragePremise: coveragePremise,
                                         railFarePremise: railFarePremise,
                                         carCarbonPremise: adacCarbon.note,
                                         lang: lang),
                lang: lang, settings: aiSettings),
           let reordered = applyDecision(decision, to: plans) {
            plans = reordered
            aiReason = decision.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            plans = sort(plans, urgency: urgency, preference: input.profile.preference, modeIntent: modeIntent)
        }

        var text = composeNarrative(origin: origin, destination: destination,
                                    driving: driving, urgency: urgency,
                                    profile: input.profile, plans: plans,
                                    modeIntent: modeIntent, aiReason: aiReason,
                                    searchEvidence: searchEvidence)

        // 若 AI 已参与决策（理由由 AI 生成），则不再额外润色，避免二次请求；
        // 仅在 AI 未决策但可用时，用 AI 润色本地文案。
        if aiReason == nil, searchEvidence.isEmpty, let aiSettings, aiSettings.isUsable,
           let polished = await ai.polish(text: text, lang: lang, settings: aiSettings) {
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

        let segment = PlanSegment(mode: .subway, detail: tr("公共交通", "Public transit"),
                                  distanceKm: distance, durationHours: hours, cost: 0,
                                  currencyCode: currency,
                                  departureDate: transit?.expectedDepartureDate)
        let navLeg = NavLeg(label: tr("公共交通导航", "Transit navigation"),
                            source: origin.mapItem, destination: destination.mapItem,
                            transport: .transit, polyline: nil)

        return CommutePlan(
            mode: .transit,
            segments: [segment],
            cost: 0,
            durationHours: hours,
            carbonKg: distance * Const.transitCarbonPerKm,
            highlight: nil,
            summary: profile.transitCard.coversTransitFully
                ? tr("AI 会先确认通票适用范围。", "AI checks pass coverage first.")
                : tr("无需停车。", "No parking needed."),
            currencyCode: currency,
            costIsComplete: true,
            navLegs: [navLeg]
        )
    }

    private struct BuiltPlan {
        let plan: CommutePlan
        let searchEvidence: [String]
    }

    private func makeCarPlan(origin: ResolvedPlace, destination: ResolvedPlace,
                             driving: RouteLeg, profile: UserProfile, currency: String,
                             carCarbonKgPerKm: Double,
                             carbonSourceNote: String?,
                             lang: Lang,
                             aiSettings: AISettings?) async -> BuiltPlan {
        let fuelCost = profile.car.energyCostPerKm * driving.distanceKm
        let parkQuote = await parkingFeeQuote(
            placeText: placeText(destination),
            contextText: tr("市区/目的地附近停车，优先估算 2 小时停车费",
                            "Downtown / destination parking, prefer a 2-hour estimate"),
            currency: currency,
            lang: lang,
            settings: aiSettings
        )
        let parkFee = parkQuote.quote.amount ?? 0
        let parkDetail = parkingDetail(prefix: tr("市中心停车", "Downtown parking"), result: parkQuote)
        let segments = [
            PlanSegment(mode: .drive, detail: tr("驾车直达", "Drive all the way"),
                        distanceKm: driving.distanceKm, durationHours: driving.travelHours, cost: fuelCost,
                        currencyCode: currency),
            PlanSegment(mode: .park, detail: parkDetail,
                        distanceKm: 0, durationHours: Const.cityParkingSearchHours, cost: parkFee,
                        currencyCode: currency)
        ]
        let navLeg = NavLeg(label: tr("驾车导航", "Driving navigation"),
                            source: origin.mapItem, destination: destination.mapItem,
                            transport: .automobile, polyline: driving.polyline)

        let baseSummary = appendCarbonSource(
            to: tr("门到门最直接，适合赶时间或多人同行；市中心停车费较高。",
                   "Most direct door-to-door; good when rushed or with companions, but downtown parking is pricey."),
            sourceNote: carbonSourceNote
        )

        let plan = CommutePlan(
            mode: .car,
            segments: segments,
            cost: fuelCost + parkFee,
            durationHours: driving.travelHours + Const.cityParkingSearchHours,
            carbonKg: driving.distanceKm * carCarbonKgPerKm,
            highlight: nil,
            summary: appendRideshareSuggestion(to: baseSummary, carbonKg: driving.distanceKm * carCarbonKgPerKm),
            currencyCode: currency,
            costIsComplete: parkQuote.quote.isKnown,
            navLegs: [navLeg],
            rideshareURL: blablacarURL()
        )
        return BuiltPlan(plan: plan, searchEvidence: parkQuote.evidence.map { [$0] } ?? [])
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
                                  dbLots: [ParkRideLotInfo],
                                  carCarbonKgPerKm: Double,
                                  carbonSourceNote: String?,
                                  lang: Lang,
                                  aiSettings: AISettings?) async -> BuiltPlan? {
        // 1) 候选停车场：只考虑目的地 20km 内的真实 P+R / 停车换乘点；
        //    数据库没有覆盖该地区时，回落到以目的地为中心的 MapKit 搜索。
        let tripStraightKm = RouteService.straightLineKm(origin.coordinate, destination.coordinate)
        let searchPoint = destination.coordinate
        let nearbyDB = dbLots
            .filter {
                isValidParkRideCandidate(lotCoordinate: $0.coordinate,
                                         origin: origin.coordinate,
                                         destination: destination.coordinate,
                                         tripStraightKm: tripStraightKm)
            }

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
            lotItems = await routeService.searchParkAndRideLots(
                near: searchPoint,
                radiusMeters: Const.prMaxDistanceToDestinationKm * 1000,
                maxResults: 20
            )
                .filter {
                    isValidParkRideCandidate(lotCoordinate: $0.placemark.coordinate,
                                             origin: origin.coordinate,
                                             destination: destination.coordinate,
                                             tripStraightKm: tripStraightKm)
                }
        }
        guard !lotItems.isEmpty else { return nil }

        // 2) 对所有停车场做本地快速预估（不调用 API），按预估总时间排序。
        let ranked = TimeEstimationManager.rankedCandidates(origin: origin.coordinate,
                                                            destination: destination.coordinate,
                                                            lots: lotItems)

        // 3) 只取预估最优的前 5 个，调 Apple Maps API 做真实路径验证。
        let candidates = Array(ranked.prefix(6))

        // 4) 对前 6 个用真实路线计算「驾车到停车场 + 公交到目的地」并取总时间最优者。
        var best: EvaluatedPR?
        for candidate in candidates {
            let lotCoord = candidate.lot.placemark.coordinate
            // 避免选到离起点太近或就在终点的「停车场」。
            let driveStraight = RouteService.straightLineKm(origin.coordinate, lotCoord)
            let toDestStraight = RouteService.straightLineKm(lotCoord, destination.coordinate)
            guard driveStraight > 1.0,
                  isValidParkRideCandidate(lotCoordinate: lotCoord,
                                           origin: origin.coordinate,
                                           destination: destination.coordinate,
                                           tripStraightKm: tripStraightKm) else { continue }

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

        let parkQuote = await parkingFeeQuote(
            placeText: "\(lotNameForSearch(lot: lot, info: info)), \(info?.address ?? "")",
            contextText: tr("P+R 停车场，优先搜索日票/单次停车费，其次每小时费率",
                            "P+R lot, prefer day/single-session parking fee, otherwise hourly rate"),
            currency: currency,
            lang: lang,
            settings: aiSettings
        )
        let parkFee = parkQuote.quote.amount ?? 0
        let costComplete = parkQuote.quote.isKnown

        let lotName = info?.name ?? lot.name ?? tr("换乘停车场", "Park & Ride lot")
        // 停车费说明：用户填了一口价则用之；否则若数据库有每小时价，展示真实费率（时长不定，不计入总价）。
        var parkDetail: String
        if parkQuote.quote.isKnown {
            parkDetail = parkingDetail(prefix: tr("停车换乘", "Park & switch"), result: parkQuote)
        } else if let rate = info?.pricePerHour, rate > 0 {
            let rateText = CurrencyFormat.string(rate, code: currency)
            parkDetail = tr("停车换乘（参考 \(rateText)/小时）",
                            "Park & switch (~\(rateText)/h reference)")
        } else {
            parkDetail = tr("停车换乘（未查到）", "Park & switch (not found)")
        }

        // 公交段说明：附上数据库里的真实换乘线路。
        let lines = (info?.publicTransport ?? "").trimmingCharacters(in: .whitespaces)
        var transitDetail = tr("公共交通", "Public transit")
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
                        distanceKm: transitDistance, durationHours: transitHours, cost: 0,
                        currencyCode: currency,
                        departureDate: transitLeg?.expectedDepartureDate)
        ]
        let total = driveCost + parkFee
        let time = driveLeg.travelHours + Const.prParkSwitchHours + transitHours
        let carbon = driveLeg.distanceKm * carCarbonKgPerKm + transitDistance * Const.transitCarbonPerKm

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
        summary = appendCarbonSource(to: summary, sourceNote: carbonSourceNote)
        summary = appendRideshareSuggestion(to: summary, carbonKg: carbon)

        let plan = CommutePlan(
            mode: .parkAndRide,
            segments: segments,
            cost: total,
            durationHours: time,
            carbonKg: carbon,
            highlight: nil,
            summary: summary,
            currencyCode: currency,
            costIsComplete: costComplete,
            navLegs: navLegs,
            rideshareURL: blablacarURL()
        )
        return BuiltPlan(plan: plan, searchEvidence: parkQuote.evidence.map { [$0] } ?? [])
    }

    // MARK: - 计费

    private struct CarCarbonInput {
        let kgCO2PerKm: Double
        let note: String?
    }

    private func carCarbonEstimateIfNeeded(profile: UserProfile, lang: Lang, settings: AISettings?) async -> CarCarbonInput {
        guard profile.hasCar else { return CarCarbonInput(kgCO2PerKm: 0, note: nil) }
        return await carCarbonEstimate(profile: profile, lang: lang, settings: settings)
    }

    private func carCarbonEstimate(profile: UserProfile, lang: Lang, settings: AISettings?) async -> CarCarbonInput {
        if let grams = profile.car.co2GramsPerKm, grams > 0 {
            let note = lang == .zh
                ? "汽车 CO2：使用你填写的 \(Int(grams.rounded())) g/km"
                : "Car CO2: using your entered \(Int(grams.rounded())) g/km"
            return CarCarbonInput(kgCO2PerKm: grams / 1000.0, note: note)
        }

        let fallback = fallbackCarbonPerKm(for: profile.car)
        let grams = Int((fallback * 1000).rounded())
        let note = lang == .zh
            ? "汽车 CO2：未填写，暂用本地估算 \(grams) g/km"
            : "Car CO2: not entered, using local fallback \(grams) g/km"
        return CarCarbonInput(kgCO2PerKm: fallback, note: note)
    }

    private func shouldLookupRailFare(transit: RouteLeg?, driving: RouteLeg?) -> Bool {
        let distance = transit?.distanceKm ?? driving?.distanceKm ?? 0
        return distance >= 30
    }

    private func fallbackCarbonPerKm(for car: CarProfile) -> Double {
        car.fuelType == .electric ? Const.evCarbonPerKm : Const.carCarbonPerKm
    }

    private func appendCarbonSource(to summary: String, sourceNote: String?) -> String {
        guard let sourceNote, !sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return summary
        }
        return summary + tr("｜\(sourceNote)", " | \(sourceNote)")
    }

    private func appendRideshareSuggestion(to summary: String, carbonKg: Double) -> String {
        let twoPeople = carbonKg / 2.0
        let threePeople = carbonKg / 3.0
        return summary + tr(
            "｜可考虑顺风车/拼车：2 人同行约 \(String(format: "%.1f", twoPeople)) kg CO₂/人，3 人同行约 \(String(format: "%.1f", threePeople)) kg CO₂/人。",
            " | Consider carpooling: with 2 people ~\(String(format: "%.1f", twoPeople)) kg CO₂/person, with 3 people ~\(String(format: "%.1f", threePeople)) kg CO₂/person."
        )
    }

    private func blablacarURL() -> URL? {
        URL(string: "https://www.blablacar.de/search-car-sharing")
    }

    private struct ParkingFeeInput {
        let quote: PriceQuote
        let evidence: String?
        let shortSource: String?
    }

    private func parkingFeeQuote(placeText: String,
                                 contextText: String,
                                 currency: String,
                                 lang: Lang,
                                 settings: AISettings?) async -> ParkingFeeInput {
        guard let settings, settings.isUsable else {
            return ParkingFeeInput(
                quote: .unknown,
                evidence: tr("停车费：未搜索（后台 AI 未开启或未配置）。",
                             "Parking fee: not searched (Background AI is off or not configured)."),
                shortSource: nil
            )
        }
        let estimate = await ai.parkingFeeEstimate(placeText: placeText,
                                                   contextText: contextText,
                                                   currencyCode: currency,
                                                   lang: lang,
                                                   settings: settings)
        guard let estimate else {
            return ParkingFeeInput(
                quote: .unknown,
                evidence: tr("停车费：未查到（\(placeText)）。",
                             "Parking fee: not found (\(placeText))."),
                shortSource: nil
            )
        }

        let quote = estimate.quote(expectedCurrency: currency)
        let amountText = quote.amount.map { CurrencyFormat.string($0, code: currency) }
            ?? tr("未查到", "not found")
        let source = estimate.sourceSummary
        let note = estimate.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = tr("停车费：\(placeText) → \(amountText)；来源：\(source)\(note.isEmpty ? "" : "；说明：\(note)")",
                          "Parking fee: \(placeText) → \(amountText); source: \(source)\(note.isEmpty ? "" : "; note: \(note)")")
        let shortSource = estimate.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParkingFeeInput(quote: quote, evidence: evidence, shortSource: shortSource?.isEmpty == false ? shortSource : nil)
    }

    private func parkingDetail(prefix: String, result: ParkingFeeInput) -> String {
        if result.quote.isKnown {
            if let shortSource = result.shortSource {
                return tr("\(prefix)（联网：\(shortSource)）",
                          "\(prefix) (online: \(shortSource))")
            }
            return tr("\(prefix)（联网搜索）", "\(prefix) (online lookup)")
        }
        return tr("\(prefix)（未查到）", "\(prefix) (not found)")
    }

    private func placeText(_ place: ResolvedPlace) -> String {
        place.subtitle.isEmpty ? place.name : "\(place.name), \(place.subtitle)"
    }

    private func lotNameForSearch(lot: MKMapItem, info: ParkRideLotInfo?) -> String {
        info?.name ?? lot.name ?? tr("P+R 停车场", "P+R parking lot")
    }

    private func isValidParkRideCandidate(lotCoordinate: CLLocationCoordinate2D,
                                          origin: CLLocationCoordinate2D,
                                          destination: CLLocationCoordinate2D,
                                          tripStraightKm: Double) -> Bool {
        let originToDest = max(tripStraightKm, 0.1)
        let originToLot = RouteService.straightLineKm(origin, lotCoordinate)
        let lotToDest = RouteService.straightLineKm(lotCoordinate, destination)

        // P+R 必须更靠近目的地：避免选到起点附近或绕路方向的停车场。
        guard originToLot > 1.0,
              lotToDest >= Const.prMinRemainingDistanceKm,
              lotToDest < originToDest,
              originToLot < originToDest,
              lotToDest <= Const.prMaxDistanceToDestinationKm else {
            return false
        }
        return true
    }

    // MARK: - AI 决策辅助

    /// 把每个候选方案压成一行真实数据摘要，供 AI 选择 / 排序（不含编造）。
    private func planSummaries(_ plans: [CommutePlan], lang: Lang) -> [String] {
        plans.map { plan in
            let segs = plan.segments
                .map { "\($0.mode.displayName) \($0.durationText)" }
                .joined(separator: " + ")
            let costNote = plan.costIsComplete
                ? ""
                : (lang == .zh ? "（含未填停车费，实际更高）" : " (has unset parking fees, actually higher)")
            let costLabel = lang == .zh ? "汽车/停车费用" : "driving/parking cost"
            if plan.mode == .transit {
                if lang == .zh {
                    return "\(plan.mode.displayName)：总时间 \(plan.durationText)，碳排放 \(plan.carbonText)；路线：\(segs)"
                } else {
                    return "\(plan.mode.displayName): total time \(plan.durationText), carbon \(plan.carbonText); route: \(segs)"
                }
            }
            if lang == .zh {
                return "\(plan.mode.displayName)：总时间 \(plan.durationText)，\(costLabel) \(plan.costText)\(costNote)，碳排放 \(plan.carbonText)；路线：\(segs)"
            } else {
                return "\(plan.mode.displayName): total time \(plan.durationText), \(costLabel) \(plan.costText)\(costNote), carbon \(plan.carbonText); route: \(segs)"
            }
        }
    }

    private func decisionContext(origin: ResolvedPlace, destination: ResolvedPlace,
                                 driving: RouteLeg?, urgency: Urgency,
                                 profile: UserProfile, userText: String,
                                 modeIntent: ModeIntent,
                                 ticketCoveragePremise: String?,
                                 railFarePremise: String?,
                                 carCarbonPremise: String?,
                                 lang: Lang) -> String {
        let note = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if lang == .zh {
            var s = "行程：\(origin.name) → \(destination.name)；紧急程度：\(urgency.displayName)；用户本次方式意图：\(modeIntent.displayNameZh)；默认偏好：\(profile.preference.displayName)；交通卡：\(profile.transitCard.displayName)；是否有车：\(profile.hasCar ? "有" : "无")"
            if !note.isEmpty { s += "；用户描述：\(note)" }
            if let premise = ticketCoveragePremise?.trimmingCharacters(in: .whitespacesAndNewlines), !premise.isEmpty {
                s += "\n票种适用范围前提（联网搜索结果）：\(premise)"
            }
            if let railFarePremise = railFarePremise?.trimmingCharacters(in: .whitespacesAndNewlines), !railFarePremise.isEmpty {
                s += "\nDB 火车票价证据（只作说明和判断依据，不显示为公交方案费用）：\(railFarePremise)"
            }
            if let carCarbonPremise = carCarbonPremise?.trimmingCharacters(in: .whitespacesAndNewlines), !carCarbonPremise.isEmpty {
                s += "\n汽车碳排放前提：\(carCarbonPremise)"
            }
            return s
        } else {
            var s = "Trip: \(origin.name) → \(destination.name); urgency: \(urgency.displayName); user's mode intent this trip: \(modeIntent.displayNameEn); default preference: \(profile.preference.displayName); transit card: \(profile.transitCard.displayName); has car: \(profile.hasCar ? "yes" : "no")"
            if !note.isEmpty { s += "; user note: \(note)" }
            if let premise = ticketCoveragePremise?.trimmingCharacters(in: .whitespacesAndNewlines), !premise.isEmpty {
                s += "\nTicket coverage premise (online search result): \(premise)"
            }
            if let railFarePremise = railFarePremise?.trimmingCharacters(in: .whitespacesAndNewlines), !railFarePremise.isEmpty {
                s += "\nDB rail-fare evidence (for explanation and judgment only, not shown as the transit plan cost): \(railFarePremise)"
            }
            if let carCarbonPremise = carCarbonPremise?.trimmingCharacters(in: .whitespacesAndNewlines), !carCarbonPremise.isEmpty {
                s += "\nCar carbon-emissions premise: \(carCarbonPremise)"
            }
            return s
        }
    }

    /// 校验 AI 给出的排序是 0..<count 的合法排列，再据此重排；非法则返回 nil。
    private func applyDecision(_ decision: AIService.PlanDecision, to plans: [CommutePlan]) -> [CommutePlan]? {
        let n = plans.count
        var order = decision.order.filter { $0 >= 0 && $0 < n }
        // 去重，保持首次出现顺序。
        var seen = Set<Int>()
        order = order.filter { seen.insert($0).inserted }
        // 把缺失的索引按原顺序补到末尾，保证不丢方案。
        for i in 0..<n where !seen.contains(i) { order.append(i) }
        guard order.count == n else { return nil }
        // 若 AI 指定了 bestIndex 且合法，置于首位。
        if decision.bestIndex >= 0, decision.bestIndex < n,
           let pos = order.firstIndex(of: decision.bestIndex) {
            order.remove(at: pos)
            order.insert(decision.bestIndex, at: 0)
        }
        return order.map { plans[$0] }
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

    private func detectModeIntent(_ text: String) -> ModeIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .any }
        let lower = trimmed.lowercased()

        let parkRideZh = ["p+r", "park and ride", "停车换乘", "换乘停车", "停到郊区", "停在城外", "停车再坐"]
        let parkRideEn = ["p+r", "park and ride", "park & ride", "park then ride", "park outside"]
        if parkRideZh.contains(where: trimmed.contains) || parkRideEn.contains(where: lower.contains) {
            return .parkRide
        }

        let driveZh = ["开车", "自驾", "驾车", "开过去", "开到", "开车去", "开车到", "只开车", "不要公交", "不坐公交", "不用公交", "不坐公共交通"]
        let driveEn = ["drive", "driving", "by car", "take my car", "no transit", "don't take transit", "do not take transit", "avoid transit", "no bus"]
        if driveZh.contains(where: trimmed.contains) || driveEn.contains(where: lower.contains) {
            return .driving
        }

        let transitZh = ["公交", "公共交通", "地铁", "轻轨", "电车", "tram", "u-bahn", "s-bahn", "坐车去", "坐地铁", "坐公交"]
        let transitEn = ["public transit", "transit", "bus", "metro", "subway", "tram", "train", "u-bahn", "s-bahn"]
        if transitZh.contains(where: trimmed.contains) || transitEn.contains(where: lower.contains) {
            return .transit
        }

        return .any
    }

    private func filter(_ plans: [CommutePlan], for intent: ModeIntent) -> [CommutePlan] {
        guard !plans.isEmpty else { return plans }
        switch intent {
        case .any:
            return plans
        case .transit:
            let filtered = plans.filter { $0.mode == .transit }
            return filtered.isEmpty ? plans : filtered
        case .parkRide:
            let filtered = plans.filter { $0.mode == .parkAndRide }
            return filtered.isEmpty ? plans.filter { $0.mode != .transit } : filtered
        case .driving:
            let drivePlans = plans.filter { $0.mode == .car || $0.mode == .parkAndRide }
            guard !drivePlans.isEmpty else { return plans }
            var result = drivePlans
            if let transitPlan = plans.first(where: { $0.mode == .transit }),
               let bestDrive = drivePlans.min(by: { $0.durationHours < $1.durationHours }),
               shouldShowTransitDespiteDrivingIntent(transit: transitPlan, bestDrive: bestDrive) {
                result.append(transitPlan)
            }
            return result
        }
    }

    private func shouldShowTransitDespiteDrivingIntent(transit: CommutePlan, bestDrive: CommutePlan) -> Bool {
        transit.durationHours <= bestDrive.durationHours * 0.85
            || bestDrive.durationHours - transit.durationHours >= 10.0 / 60.0
    }

    // MARK: - 排序与高亮

    private func annotateHighlights(_ plans: inout [CommutePlan]) {
        let cheapestTag = tr("最省钱", "Cheapest")
        let fastestTag = tr("最快", "Fastest")
        let greenestTag = tr("最环保", "Greenest")
        if let cheapest = plans.filter({ $0.mode != .transit }).min(by: { $0.cost < $1.cost }),
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

    private func sort(_ plans: [CommutePlan], urgency: Urgency, preference: CommutePreference, modeIntent: ModeIntent) -> [CommutePlan] {
        if urgency == .urgent {
            return plans.sorted { $0.durationHours < $1.durationHours }
        }
        if modeIntent == .driving {
            return plans.sorted {
                if $0.mode == .transit, $1.mode != .transit { return false }
                if $1.mode == .transit, $0.mode != .transit { return true }
                return score($0, urgency: urgency) > score($1, urgency: urgency)
            }
        }
        switch preference {
        case .cheapest: return plans.sorted { costRankValue($0) < costRankValue($1) }
        case .fastest:  return plans.sorted { $0.durationHours < $1.durationHours }
        case .greenest: return plans.sorted { $0.carbonKg < $1.carbonKg }
        case .balanced: return plans.sorted { score($0, urgency: urgency) > score($1, urgency: urgency) }
        }
    }

    private func score(_ plan: CommutePlan, urgency: Urgency) -> Double {
        let costWeight = urgency == .relaxed ? 5000.0 : 3000.0
        let timeWeight = urgency == .relaxed ? 2.0 : 5.0
        return (1.0 / (costRankValue(plan) + 1)) * costWeight + (1.0 / (plan.durationHours + 0.2)) * timeWeight
    }

    private func costRankValue(_ plan: CommutePlan) -> Double {
        plan.mode == .transit ? Double.greatestFiniteMagnitude / 2 : plan.cost
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
                                  profile: UserProfile, plans: [CommutePlan],
                                  modeIntent: ModeIntent,
                                  aiReason: String?,
                                  searchEvidence: [String]) -> String {
        var lines: [String] = []
        if let driving {
            let dist = formatDistance(driving.distanceKm)
            lines.append(tr(
                "已分析 \(origin.name) → \(destination.name)（驾车约 \(dist)，\(urgency.displayName)）。",
                "Analyzed \(origin.name) → \(destination.name) (driving ~\(dist), \(urgency.displayName))."
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
        } else if modeIntent != .any {
            lines.append(tr("已按你的「\(modeIntent.displayNameZh)」意图筛选方案。",
                            "Filtered plans by your \"\(modeIntent.displayNameEn)\" intent."))
        }

        if let best = plans.first {
            let metric = recommendationMetricText(for: best)
            if let aiReason, !aiReason.isEmpty {
                // AI 决策结果：用 AI 的理由 + 真实数字。
                lines.append(tr(
                    "AI 综合分析后推荐「\(best.mode.displayName)」：\(metric)。\(aiReason)",
                    "After AI analysis, I recommend \(best.mode.displayName): \(metric). \(aiReason)"
                ))
            } else {
                switch urgency {
                case .urgent:
                    lines.append(tr("赶时间，优先推荐最快的「\(best.mode.displayName)」：\(metric)。",
                                    "In a hurry — fastest is \(best.mode.displayName): \(metric)."))
                case .relaxed:
                    lines.append(tr("不赶时间，优先推荐「\(best.mode.displayName)」：\(metric)。",
                                    "Not rushed — I recommend \(best.mode.displayName): \(metric)."))
                case .normal:
                    lines.append(tr("综合成本与时间，推荐「\(best.mode.displayName)」：\(metric)。",
                                    "Balancing cost and time, I recommend \(best.mode.displayName): \(metric)."))
                }
            }
        }
        if plans.contains(where: { !$0.costIsComplete }) {
            lines.append(tr(
                "注：停车费由 Agent 联网搜索，未查到的停车费不计入汽车/停车费用（显示为「≥」）。",
                "Note: parking fees are searched online by the agent, and fees not found online are excluded from driving/parking cost (shown as \"≥\")."
            ))
        }
        if !searchEvidence.isEmpty {
            let evidence = searchEvidence
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqued()
            if !evidence.isEmpty {
                lines.append(tr("联网搜索结果：\n", "Online lookup results:\n") + evidence.map { "• \($0)" }.joined(separator: "\n"))
            }
        }
        lines.append(tr("点方案里的「导航」可直接用 Apple 地图出发 👇", "Tap \"Navigate\" in a plan to start in Apple Maps 👇"))
        return lines.joined(separator: "\n")
    }

    private func recommendationMetricText(for plan: CommutePlan) -> String {
        if plan.mode == .transit {
            return plan.durationText
        }
        return tr("汽车/停车费用 \(plan.costText)、\(plan.durationText)",
                  "driving/parking cost \(plan.costText), \(plan.durationText)")
    }

    private func formatDistance(_ km: Double) -> String {
        km >= 10
            ? tr("\(Int(km.rounded())) 公里", "\(Int(km.rounded())) km")
            : tr(String(format: "%.1f 公里", km), String(format: "%.1f km", km))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
