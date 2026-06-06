import Foundation
import SwiftUI
import MapKit

/// 主界面状态：起终点（真实地点）、聊天记录、调用 Agent 规划。
@MainActor
final class PlannerViewModel: ObservableObject {
    @Published var originText: String = ""
    @Published var destinationText: String = ""
    @Published var inputText: String = ""
    @Published var originPlace: ResolvedPlace?
    @Published var destinationPlace: ResolvedPlace?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isProcessing: Bool = false

    private let planner = CommutePlanner()
    /// 仅用于把自由文本解析成坐标（与界面联想用的实例分离）。
    private let resolver = LocationSearchService()
    /// 后台 AI（可选）：联网查德国票种适用范围 / 给选择建议。
    private let aiService = AIService()
    private var profileProvider: () -> UserProfile
    private var profileSaver: (UserProfile) -> Void = { _ in }
    private var awaitingCarSetup = false

    /// 最近一次成功规划的完整行程上下文。后续纯对话（如“那还是开车吧”）会沿用它。
    private var lastOrigin: ResolvedPlace?
    private var lastDestination: ResolvedPlace?
    private var lastTripSummary: String = ""

    /// 程序化设置地点（定位/联想选择）时置位，避免随之而来的文本变更回调把刚设好的地点清空。
    private var ignoreNextOriginTextChange = false
    private var ignoreNextDestinationTextChange = false

    init(profileProvider: @escaping () -> UserProfile = { .default }) {
        self.profileProvider = profileProvider
        appendWelcome()
    }

    func updateProfileProvider(_ provider: @escaping () -> UserProfile,
                               saver: @escaping (UserProfile) -> Void = { _ in }) {
        self.profileProvider = provider
        self.profileSaver = saver
        promptForCarSetupIfNeeded()
    }

    private func appendWelcome() {
        messages.append(
            ChatMessage(
                role: .assistant,
                text: tr(
                    "你好，我是 Drive&Ride 出行助手 🅿️🚇\n在上方设置出发地和目的地，再描述需求（如「有点赶」「想省钱」）。我会比较公交、自驾、P+R 的时间、碳排和停车信息。",
                    "Hi, I'm your Drive&Ride assistant 🅿️🚇\nSet your origin and destination above, then describe what you need (e.g. \"a bit rushed\", \"save money\"). I'll compare transit, driving, and Park & Ride by time, CO₂, and parking info."
                )
            )
        )
    }

    private func promptForCarSetupIfNeeded() {
        guard !isProcessing else { return }
        let profile = profileProvider()
        guard profile.hasCar, !profile.car.isConfigured, !awaitingCarSetup else { return }
        awaitingCarSetup = true
        messages.append(ChatMessage(
            role: .assistant,
            text: tr("第一次使用前，先告诉我你的车型信息吧。请直接输入品牌、型号、年份/版本；如果知道能源类型和百公里能耗也一起写，例如：VW Golf 1.5 TSI 2021，汽油，6.2 L/100km。没有车也可以点下面。",
                     "Before the first trip, tell me your car. Enter brand, model, year/trim, and optionally fuel type and consumption, e.g. VW Golf 1.5 TSI 2021, gasoline, 6.2 L/100km. If you don't have a car, use the option below."),
            quickReplies: [tr("我没有车", "I don't have a car")]
        ))
    }

    func setOrigin(_ place: ResolvedPlace) {
        ignoreNextOriginTextChange = (place.name != originText)
        originPlace = place
        originText = place.name
    }

    func setDestination(_ place: ResolvedPlace) {
        ignoreNextDestinationTextChange = (place.name != destinationText)
        destinationPlace = place
        destinationText = place.name
    }

    /// 用户编辑了输入框文本：若与已选地点名不一致，则使已解析地点失效。
    func originTextChanged() {
        if ignoreNextOriginTextChange {
            ignoreNextOriginTextChange = false
            return
        }
        if originPlace?.name != originText { originPlace = nil }
    }

    func destinationTextChanged() {
        if ignoreNextDestinationTextChange {
            ignoreNextDestinationTextChange = false
            return
        }
        if destinationPlace?.name != destinationText { destinationPlace = nil }
    }

    func submit() {
        var extra = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        if awaitingCarSetup {
            handleCarSetup(extra)
            return
        }

        let parsed = parseTripText(extra)
        applyParsedTrip(parsed)
        extra = parsed.note

        let userVisible = composeUserMessage(extra: extra)
        if !userVisible.isEmpty {
            messages.append(ChatMessage(role: .user, text: userVisible))
        }
        runPlanning(extraText: extra)
    }

    func sendQuickReply(_ text: String) {
        if awaitingCarSetup {
            handleCarSetup(text)
            return
        }
        messages.append(ChatMessage(role: .user, text: text))
        runPlanning(extraText: text)
    }

    /// 语音模式：提交 ASR 识别文本并返回助手回复（供 TTS 朗读）。
    func submitVoice(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if awaitingCarSetup {
            handleCarSetup(trimmed)
            return tr("已保存车型信息。", "Saved car information.")
        }

        let parsed = parseTripText(trimmed)
        applyParsedTrip(parsed)

        let extra = parsed.note
        inputText = extra
        let userVisible = composeUserMessage(extra: extra)
        messages.append(ChatMessage(role: .user, text: userVisible.isEmpty ? trimmed : userVisible))
        inputText = ""

        return await runPlanningAsync(extraText: extra)
    }

    private struct ParsedVoiceTrip {
        let origin: String?
        let destination: String?
        let note: String
    }

    private func parseTripText(_ text: String) -> ParsedVoiceTrip {
        let normalized = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = parseTripText(normalized, pattern: #"(?i)(?:^|[\s,.;])from\s+(.+?)\s+(?:to|towards?|heading to)\s+(.+)$"#) {
            return parsed
        }
        if let parsed = parseTripText(normalized, pattern: #".*?(?:从|由)\s*(.+?)\s*(?:到|去|前往|至)\s*(.+)$"#) {
            return parsed
        }
        if originText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let parsed = parseTripText(normalized, pattern: #"^(.+?)\s*(?:到|去|前往|至|->|→)\s*(.+)$"#) {
            return parsed
        }

        return ParsedVoiceTrip(origin: nil, destination: nil, note: text)
    }

    private func parseTripText(_ text: String, pattern: String) -> ParsedVoiceTrip? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let originRange = Range(match.range(at: 1), in: text),
              let tailRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        let origin = cleanPlace(String(text[originRange]))
        let split = splitDestinationAndNote(String(text[tailRange]))
        let destination = cleanPlace(split.destination)
        guard !origin.isEmpty, !destination.isEmpty else { return nil }
        return ParsedVoiceTrip(origin: origin, destination: destination, note: split.note)
    }

    private func applyParsedTrip(_ parsed: ParsedVoiceTrip) {
        if let origin = parsed.origin {
            originPlace = nil
            ignoreNextOriginTextChange = true
            originText = origin
        }
        if let destination = parsed.destination {
            destinationPlace = nil
            ignoreNextDestinationTextChange = true
            destinationText = destination
        }
    }

    private func splitDestinationAndNote(_ text: String) -> (destination: String, note: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [",", ";", "."]
        let separatorIndex = separators
            .compactMap { sep in trimmed.range(of: sep)?.lowerBound }
            .min()
        if let separatorIndex {
            let dest = String(trimmed[..<separatorIndex])
            let noteStart = trimmed.index(after: separatorIndex)
            return (dest, String(trimmed[noteStart...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let markers = [
            "有点赶", "赶时间", "想省钱", "尽快", "快点", "不急", "正常通勤", "尽量环保",
            "a bit rushed", "in a hurry", "save money", "asap", "no rush", "go green"
        ]
        let markerIndex = markers
            .compactMap { marker -> String.Index? in
                trimmed.range(of: marker, options: [.caseInsensitive])?.lowerBound
            }
            .min()
        if let markerIndex {
            let dest = String(trimmed[..<markerIndex])
            let note = String(trimmed[markerIndex...])
            return (dest, note.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return (trimmed, "")
    }

    private func cleanPlace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "我想", with: "")
            .replacingOccurrences(of: "我要", with: "")
            .replacingOccurrences(of: "请", with: "")
            .replacingOccurrences(of: "导航", with: "")
            .replacingOccurrences(of: "出发", with: "")
            .replacingOccurrences(of: "go ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "navigate ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func handleCarSetup(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))

        var profile = profileProvider()
        if isNoCarAnswer(trimmed) {
            profile.hasCar = false
            profileSaver(profile)
            awaitingCarSetup = false
            messages.append(ChatMessage(
                role: .assistant,
                text: tr("已记录为无车。之后我只比较公共交通方案。",
                         "Got it. I'll compare public-transit options only.")
            ))
            return
        }

        profile.hasCar = true
        let modelName = extractCarModel(from: trimmed)
        guard !modelName.isEmpty else {
            messages.append(ChatMessage(
                role: .assistant,
                text: tr("我没识别到具体车型。请直接输入品牌、型号和年份，例如：Civic Type R 2008。",
                         "I couldn't identify the model. Please enter the brand, model, and year, e.g. Civic Type R 2008.")
            ))
            return
        }
        profile.car.name = modelName
        profile.car.fuelType = inferFuelType(from: trimmed) ?? profile.car.fuelType
        if let consumption = inferConsumption(from: trimmed) {
            profile.car.consumptionPer100km = consumption
        }
        if let co2 = inferCO2GramsPerKm(from: trimmed) {
            profile.car.co2GramsPerKm = co2
        }
        profile.car.unitPrice = nil
        profile.cityParkingFee = nil
        profile.parkRideParkingFee = nil
        profileSaver(profile)
        awaitingCarSetup = false

        messages.append(ChatMessage(
            role: .assistant,
            text: tr("已保存车型：\(profile.car.name)。\n如果你填写了 CO2 g/km，我会直接用它计算；停车费仍会在规划时联网搜索。",
                     "Saved car: \(profile.car.name).\nIf you entered CO2 g/km, I'll use it directly; parking fees are still searched online during planning.")
        ))
    }

    private func extractCarModel(from text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPatterns = [
            #"^(我的|我这辆|这辆|这个)?\s*(车|汽车|车型)\s*(是|为|叫)?\s*"#,
            #"^(我开|我开的|我驾驶|我驾驶的|开的是|开的)\s*"#,
            #"(?i)^(my\s+car\s+is|my\s+vehicle\s+is|i\s+drive|i\s+have|car\s+is|vehicle\s+is)\s+"#
        ]
        for pattern in prefixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
               match.range.location == 0,
               let range = Range(match.range, in: value) {
                value.removeSubrange(range)
                break
            }
        }

        let separators = ["，", ",", "。", ".", "；", ";", "\n"]
        if let firstSeparator = separators
            .compactMap({ value.range(of: $0)?.lowerBound })
            .min() {
            value = String(value[..<firstSeparator])
        }

        return value
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func isNoCarAnswer(_ text: String) -> Bool {
        let lower = text.lowercased()
        return text.contains("没有车") || text.contains("无车") || lower.contains("no car") || lower.contains("don't have a car")
    }

    private func inferFuelType(from text: String) -> FuelType? {
        let lower = text.lowercased()
        if text.contains("电") || lower.contains("electric") || lower.contains("ev") { return .electric }
        if text.contains("柴油") || lower.contains("diesel") { return .diesel }
        if text.contains("混") || lower.contains("hybrid") { return .hybrid }
        if text.contains("汽油") || lower.contains("gasoline") || lower.contains("petrol") { return .gasoline }
        return nil
    }

    private func inferConsumption(from text: String) -> Double? {
        let pattern = #"(\d+(?:[\.,]\d+)?)\s*(?:l/100|L/100|kwh/100|kWh/100)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private func inferCO2GramsPerKm(from text: String) -> Double? {
        let pattern = #"(?i)(\d+(?:[\.,]\d+)?)\s*(?:g\s*/?\s*km|gCO2\s*/?\s*km|g\s*CO2\s*/?\s*km)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private func composeUserMessage(extra: String) -> String {
        var parts: [String] = []
        let o = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty || !d.isEmpty, routeTextShouldBeShownInUserMessage(extra: extra) {
            let blank = tr("（未填）", "(empty)")
            parts.append("\(o.isEmpty ? blank : o) → \(d.isEmpty ? blank : d)")
        }
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: tr("　·　", "  ·  "))
    }

    private func routeTextShouldBeShownInUserMessage(extra: String) -> Bool {
        guard let lastOrigin, let lastDestination else { return true }
        let currentOrigin = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentDestination = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentOrigin.isEmpty, currentOrigin != lastOrigin.name { return true }
        if !currentDestination.isEmpty, currentDestination != lastDestination.name { return true }
        let note = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty
    }

    private func runPlanning(extraText: String) {
        guard !isProcessing else { return }
        Task { _ = await runPlanningAsync(extraText: extraText) }
    }

    @discardableResult
    private func runPlanningAsync(extraText: String) async -> String? {
        guard !isProcessing else { return nil }

        let typing = ChatMessage(
            role: .assistant,
            text: tr("正在规划路线，并联网搜索停车费、DB 票价和德国票种适用范围…",
                     "Planning routes and searching online for parking fees, DB fares, and German ticket coverage..."),
            isTyping: true
        )
        messages.append(typing)
        isProcessing = true

        if originPlace == nil, !originText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            originPlace = await resolver.resolve(query: originText)
        }
        if destinationPlace == nil, !destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            destinationPlace = await resolver.resolve(query: destinationText,
                                                      near: originPlace?.coordinate)
        }

        let context = tripContextForPlanning()

        let input = PlanningInput(origin: context.origin,
                                  destination: context.destination,
                                  userText: extraText,
                                  profile: profileProvider(),
                                  parkRideLots: ParkRideDatabase.shared.cachedActiveLots())
        ParkRideDatabase.shared.prepareIfNeeded()
        let outcome = await planner.plan(input)

        var actions: [MessageAction] = []
        if !outcome.plans.isEmpty, let origin = context.origin, let dest = context.destination {
            lastOrigin = origin
            lastDestination = dest
            lastTripSummary = tripSummary(origin: origin, destination: dest, extra: extraText)
            actions.append(
                MessageAction(title: tr("🚇 该不该办张交通卡？", "🚇 Should I buy a transit card?"),
                              kind: .transitCardAdvice)
            )
        }

        messages.removeAll { $0.id == typing.id }
        messages.append(
            ChatMessage(role: .assistant, text: outcome.assistantText,
                        plans: outcome.plans, quickReplies: outcome.quickReplies,
                        actions: actions)
        )
        isProcessing = false
        return outcome.assistantText
    }

    private func tripContextForPlanning() -> (origin: ResolvedPlace?, destination: ResolvedPlace?) {
        let originQuery = originText.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationQuery = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)

        let explicitOriginChanged = !originQuery.isEmpty && (lastOrigin.map { originQuery != $0.name } ?? true)
        let explicitDestinationChanged = !destinationQuery.isEmpty && (lastDestination.map { destinationQuery != $0.name } ?? true)

        let explicitOrigin = originPlace
        let explicitDestination = destinationPlace
        return (
            explicitOrigin ?? (explicitOriginChanged ? nil : lastOrigin),
            explicitDestination ?? (explicitDestinationChanged ? nil : lastDestination)
        )
    }

    // MARK: - 联网交通卡建议

    func handleAction(_ action: MessageAction) {
        switch action.kind {
        case .transitCardAdvice: requestTransitCardAdvice()
        }
    }

    /// 让 Agent 联网搜索目的地城市/区域的德国票种适用范围并给出选择建议。
    func requestTransitCardAdvice() {
        guard !isProcessing else { return }
        let profile = profileProvider()

        guard let ai = profile.ai, ai.isUsable else {
            messages.append(ChatMessage(
                role: .assistant,
                text: tr("要联网查询德国票种的适用范围，请先到 设置 → 后台 AI 中开启并填入 API Key（支持 Qwen / OpenAI）。开启后我会自动搜索 Deutschlandticket、本地月票等是否适合这趟路线。",
                         "To look up German ticket coverage online, first enable Background AI in Settings and add an API key (Qwen / OpenAI). Once on, I'll check whether options like the Deutschlandticket or local monthly passes fit this route.")
            ))
            return
        }
        guard let dest = lastDestination else {
            messages.append(ChatMessage(
                role: .assistant,
                text: tr("先规划一次行程，我才知道你要去哪个城市，再帮你联网查交通卡。",
                         "Plan a trip first so I know which city to look up transit cards for.")
            ))
            return
        }

        messages.append(ChatMessage(role: .user,
                                    text: tr("该不该办张交通卡？", "Should I buy a transit card?")))
        let typing = ChatMessage(role: .assistant, text: "", isTyping: true)
        messages.append(typing)
        isProcessing = true

        Task {
            let currency = CurrencyFormat.currencyCode(forCountry: dest.countryCode)
            let region = dest.subtitle.isEmpty ? dest.name : "\(dest.name)（\(dest.subtitle)）"

            let resultText: String
            do {
                resultText = try await aiService.transitCardAdvice(
                    regionText: region,
                    currencyCode: currency,
                    currentCard: profile.transitCard.displayName,
                    usageText: lastTripSummary,
                    lang: AppLocale.shared.lang,
                    settings: ai
                )
            } catch {
                resultText = tr("联网查询票种适用范围失败：\(error.localizedDescription)\n\n提示：可在 设置 → 后台 AI 把「模型」改为你账号可用的型号（如 qwen-plus / qwen3-max），或检查 API Key 与网络。",
                                "Couldn't fetch ticket coverage: \(error.localizedDescription)\n\nTip: in Settings › Background AI set \"Model\" to one your account supports (e.g. qwen-plus / qwen3-max), or check the API key and network.")
            }

            messages.removeAll { $0.id == typing.id }
            messages.append(ChatMessage(role: .assistant, text: resultText))
            isProcessing = false
        }
    }

    private func tripSummary(origin: ResolvedPlace?, destination: ResolvedPlace, extra: String) -> String {
        var s = tr("通勤行程：\(origin?.name ?? "出发地") → \(destination.name)",
                   "Commute: \(origin?.name ?? "origin") → \(destination.name)")
        let note = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            s += tr("；用户补充：\(note)", "; note: \(note)")
        } else {
            s += tr("；按工作日往返通勤估计使用频率", "; assume weekday round-trip commuting frequency")
        }
        return s
    }

    func reset() {
        lastOrigin = nil
        lastDestination = nil
        lastTripSummary = ""
        messages.removeAll()
        appendWelcome()
    }

    func refreshWelcomeIfIdle() {
        guard messages.count <= 1, !isProcessing else { return }
        messages.removeAll()
        appendWelcome()
    }
}
