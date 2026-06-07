import Foundation

/// 后台 AI 服务商。OpenAI 与 Qwen（通义千问）均为 OpenAI 兼容的 Chat Completions 接口，
/// 因此共用一套客户端，仅默认 baseURL / 模型不同。
enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case qwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .qwen: return tr("Qwen 通义千问", "Qwen")
        }
    }

    /// OpenAI 兼容 baseURL（不含 /chat/completions）。
    /// Qwen 默认用海外（新加坡）接入点；国内账号可在设置里改回 https://dashscope.aliyuncs.com/compatible-mode/v1。
    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .qwen:   return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        }
    }

    /// 默认使用低延迟模型；需要更强推理时可在设置里自定义。
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4.1-mini"
        case .qwen:   return "qwen-turbo"
        }
    }
}

/// 后台 AI 设置（可选，默认关闭）。Key 仅保存在本机。
struct AISettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var provider: AIProvider = .qwen
    var apiKey: String = ""
    /// 自定义模型（留空用服务商默认）。
    var customModel: String = ""
    /// 自定义 baseURL（留空用服务商默认）。
    var customBaseURL: String = ""
    /// Qwen TTS 音色（如 Cherry、Serena）。仅语音模式使用。
    var ttsVoice: String = "Cherry"

    var effectiveModel: String {
        customModel.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultModel : customModel
    }
    var effectiveBaseURL: String {
        customBaseURL.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultBaseURL : customBaseURL
    }
    /// 是否可用：已启用且填了 Key。
    var isUsable: Bool {
        enabled && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// DashScope 原生 API 根地址（ASR / TTS 用，不含 compatible-mode）。
    var dashScopeAPIRoot: String {
        let base = effectiveBaseURL.trimmingCharacters(in: .whitespaces)
        if base.contains("dashscope-intl") { return "https://dashscope-intl.aliyuncs.com/api/v1" }
        if base.contains("dashscope.aliyuncs.com") { return "https://dashscope.aliyuncs.com/api/v1" }
        return provider == .qwen
            ? "https://dashscope-intl.aliyuncs.com/api/v1"
            : "https://dashscope-intl.aliyuncs.com/api/v1"
    }

    /// OpenAI 兼容 chat/completions 根地址（LLM / ASR 用）。
    var compatibleChatBaseURL: String {
        let base = effectiveBaseURL.trimmingCharacters(in: .whitespaces)
        if !base.isEmpty { return base }
        return provider.defaultBaseURL
    }

    static let disabled = AISettings()
}

/// AI 调用错误（携带可读信息，便于排查）。
enum AIError: LocalizedError {
    case notConfigured
    case badURL
    case server(status: Int, message: String)
    case emptyResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return tr("未配置 AI（请在设置中开启并填入 API Key）。",
                      "AI is not configured (enable it and add an API key in Settings).")
        case .badURL:
            return tr("AI 接口地址无效，请检查自定义 baseURL。",
                      "Invalid AI endpoint — check the custom base URL.")
        case let .server(status, message):
            return tr("AI 接口返回错误（HTTP \(status)）：\(message)",
                      "AI request failed (HTTP \(status)): \(message)")
        case .emptyResponse:
            return tr("AI 返回为空。", "AI returned an empty response.")
        case .timeout:
            return tr("AI 联网查询超时。", "AI online lookup timed out.")
        }
    }
}

/// 后台 AI 客户端（OpenAI 兼容）。
///
/// 当前仅用于**润色**已经算好的方案文案：保留全部真实数字 / 地名 / 时间 / 价格，
/// 不新增、不编造。未启用或失败时返回 nil，调用方回落到本地文案。
struct AIService: Sendable {

    /// 把本地生成的文案润色得更自然（同语言）。失败 / 未启用返回 nil。
    func polish(text: String, lang: Lang, settings: AISettings) async -> String? {
        guard settings.isUsable else { return nil }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「CityDrive-Ride」通勤出行助手。请把用户给出的方案说明润色得自然、友好、简洁。
            严格要求：必须原样保留所有数字、地名、时间、价格、单位与符号（如「≥」），
            不得新增、删改或编造任何信息；只优化措辞与语气。直接输出润色后的简体中文。
            """
        case .en:
            system = """
            You are the "CityDrive-Ride" commute assistant. Polish the user's plan summary to be \
            natural, friendly and concise. Strict rules: keep every number, place name, time, \
            price, unit and symbol (e.g. "≥") exactly; do not add, change, or fabricate any \
            information — only improve wording. Output the polished English text directly.
            """
        }

        return try? await chat(system: system, user: text, settings: settings)
    }

    // MARK: - AI 决策：从真实候选中选出最佳方案并排序

    /// AI 对候选方案的决策结果。索引对应传入候选的顺序。
    struct PlanDecision: Decodable {
        let bestIndex: Int
        let order: [Int]
        let reason: String
    }

    /// 联网搜索得到的停车费。amount 为 nil 表示未查到，不编造。
    struct ParkingFeeEstimate: Decodable {
        let amount: Double?
        let currencyCode: String?
        let sourceTitle: String?
        let sourceURL: String?
        let note: String

        var sourceSummary: String {
            let title = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty, let url, !url.isEmpty {
                return "\(title) (\(url))"
            }
            if let title, !title.isEmpty { return title }
            if let url, !url.isEmpty { return url }
            return note
        }

        func quote(expectedCurrency: String) -> PriceQuote {
            guard let amount else { return .unknown }
            let actual = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let actual, !actual.isEmpty, actual != expectedCurrency.uppercased() {
                return .unknown
            }
            return PriceQuote(amount: amount, source: .remote)
        }
    }

    /// DB / bahn.de 查询到的铁路票价证据。仅作为说明和判断依据，不进入公共交通费用 UI。
    struct RailFareEstimate: Decodable {
        let fareText: String?
        let sourceTitle: String?
        let sourceURL: String?
        let note: String

        var evidenceSummary: String {
            let fare = fareText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts: [String] = []
            if let fare, !fare.isEmpty { parts.append(fare) }
            if let title, !title.isEmpty { parts.append(title) }
            if let url, !url.isEmpty { parts.append(url) }
            let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { parts.append(note) }
            return parts.joined(separator: "；")
        }
    }

    /// 让 AI 在**已用真实数据算好的候选方案**中权衡、选出最佳并给出完整排序与理由。
    ///
    /// AI 只做选择 / 排序 / 解释，不得改数字、不得新增方案。失败 / 未启用返回 nil。
    func decideBestPlan(candidates: [String],
                        context: String,
                        lang: Lang,
                        settings: AISettings) async -> PlanDecision? {
        guard settings.isUsable, !candidates.isEmpty else { return nil }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「CityDrive-Ride」通勤方案决策助手。下面给你若干**已经用真实地图路线与汽车/停车成本算好**的候选方案\
            （每个带序号，含出行方式、总时间、汽车/停车费用、是否含「未填」停车费、碳排放、分段明细；公共交通候选不包含费用字段）。
            任务：综合用户的出行描述、偏好与紧急程度，在这些候选中**选出最佳方案并给出从优到次的完整排序**，并用一句话说明理由。
            严格要求：
            - 只能从给定候选中选择与排序，**不得新增方案，不得修改或编造任何数字**。
            - 如果用户上下文包含「票种适用范围前提」，必须先判断所选票种是否看起来覆盖本次公共交通段；若不覆盖或不确定，不能因为候选里显示通票边际成本为 0 就盲目推荐。
            - 如果用户上下文包含「DB 火车票价证据」，可用于解释或判断长距离铁路方案，但不得改写候选数据或在方案卡片中新增费用字段。
            - 如果用户上下文包含「汽车碳排放前提」，环保排序必须以其中的联网提取结果为准。
            - 赶时间优先总时间短的；想省钱时只比较汽车/停车费用；含「未填」停车费的方案其真实花费可能更高，比较省钱时需谨慎。
            - **只输出 JSON**，不要任何多余文字，格式：
              {"bestIndex": 最佳方案序号, "order": [按推荐度从高到低的序号数组], "reason": "中文一句话理由"}
            """
        case .en:
            system = """
            You are the "CityDrive-Ride" commute decision assistant. Below are candidate plans **already computed \
            with real map routes and driving/parking costs** (each numbered, with mode, total time, driving/parking \
            cost, whether any parking price is "not set", carbon, and per-leg details; public-transit candidates do \
            not include a cost field).
            Task: weighing the user's request, preference and urgency, **pick the best plan and give a full \
            ranking from best to worst**, with a one-sentence reason.
            Strict rules:
            - Only select and reorder the given candidates; **do not add plans or change/fabricate any numbers**.
            - If the user context includes a "ticket coverage premise", first judge whether the selected pass appears to cover this route's transit legs; if not covered or uncertain, don't blindly recommend a plan just because a pass-based marginal cost is shown as zero.
            - If the user context includes "DB rail-fare evidence", you may use it for explanation or judgment of long-distance rail plans, but do not alter candidate data or add a cost field to the plan card.
            - If the user context includes a "car carbon-emissions premise", use that online extracted basis for green ranking.
            - Prefer shorter total time when rushed; when saving money, compare only driving/parking cost; plans with "not set" parking prices may actually cost more, so be cautious when comparing cost.
            - **Output JSON only**, no extra text, in the form:
              {"bestIndex": index, "order": [indices from best to worst], "reason": "one-sentence reason in English"}
            """
        }

        let user = (lang == .zh ? "用户上下文：\n" : "User context:\n") + context
            + (lang == .zh ? "\n\n候选方案：\n" : "\n\nCandidate plans:\n")
            + candidates.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n")

        guard let raw = try? await chat(system: system, user: user, settings: settings) else { return nil }
        return Self.decodeJSON(PlanDecision.self, from: raw)
    }

    /// 从可能带 ```json 围栏 / 多余文字的回复中提取并解码 JSON。
    private static func decodeJSON<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end else { return nil }
        let json = String(raw[start...end])
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - 联网搜索：停车费 / DB 票价 / 德国票种适用范围

    /// 让 Agent 联网搜索停车费。只接受官方/可信来源；找不到返回 nil 金额。
    func parkingFeeEstimate(placeText: String,
                            contextText: String,
                            currencyCode: String,
                            lang: Lang,
                            settings: AISettings) async -> ParkingFeeEstimate? {
        guard settings.isUsable else { return nil }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「CityDrive-Ride」停车费检索助手。请联网搜索目的地或停车场的官方/可信停车费信息。
            严格要求：
            - 搜索结果必须与用户给出的地点、城市/国家或坐标附近匹配；如果来源明显是其他城市/国家（例如德国路线却查到上海），amount 必须为 null。
            - 如果地点名重名，必须用地址、国家、坐标或目的地上下文消歧；不能只凭同名停车场返回价格。
            - 优先使用停车场官网、城市/运营商页面、Parkopedia/Google Maps 明确费率等可信来源。
            - 只返回一个用于本次方案展示的实用金额：市区停车优先 2 小时估算；P+R 优先日票/单次停车费，其次每小时费率。
            - 如果找不到明确金额，amount 必须为 null；不要编造。
            - currencyCode 必须用 ISO 货币代码，例如 EUR。
            - 只输出 JSON，不要多余文字，格式：
              {"amount": 数字或null, "currencyCode": "\(currencyCode)", "sourceTitle": "来源标题或null", "sourceURL": "URL或null", "note": "一句中文说明"}
            """
        case .en:
            system = """
            You are the "CityDrive-Ride" parking-fee lookup assistant. Search online for official or trustworthy parking-fee information for the destination or parking lot.
            Strict rules:
            - The source must match the given place, city/country, or nearby coordinates; if the source is clearly in another city/country, amount must be null.
            - If the place name is ambiguous, disambiguate by address, country, coordinates, or destination context; never return a rate from a same-named but different parking lot.
            - Prefer the parking operator, city/municipal pages, Parkopedia, or Google Maps when they show explicit rates.
            - Return one practical amount for this plan: for downtown parking prefer a 2-hour estimate; for P+R prefer day/single-session parking, otherwise hourly rate.
            - If no clear amount is found, amount must be null; do not fabricate.
            - currencyCode must be an ISO currency code, e.g. EUR.
            - Output JSON only, no extra text, in the form:
              {"amount": number_or_null, "currencyCode": "\(currencyCode)", "sourceTitle": "source title or null", "sourceURL": "URL or null", "note": "one-sentence note in English"}
            """
        }

        let user = lang == .zh
            ? "地点：\(placeText)\n上下文：\(contextText)\n目标货币：\(currencyCode)\n请联网搜索停车费。"
            : "Place: \(placeText)\nContext: \(contextText)\nTarget currency: \(currencyCode)\nSearch online for parking fees."

        let raw = try? await withTimeout(seconds: 12) {
            try await chat(system: system, user: user, settings: settings, enableSearch: true)
        }
        guard let raw else { return nil }
        return Self.decodeJSON(ParkingFeeEstimate.self, from: raw)
    }

    /// 让 Agent 搜 DB / bahn.de 的铁路票价。只作证据，不进入公共交通费用 UI。
    func railFareLookupOnDB(originText: String,
                            destinationText: String,
                            routeText: String,
                            lang: Lang,
                            settings: AISettings) async -> RailFareEstimate? {
        guard settings.isUsable else { return nil }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「CityDrive-Ride」德国铁路票价检索助手。请联网搜索 Deutsche Bahn / DB 官方页面（bahn.de 或 int.bahn.de）来查找这段铁路/公共交通路线可能的火车票价。
            严格要求：
            - 优先使用 DB / bahn.de / int.bahn.de 的连接搜索、票价或订票结果页面；不要用论坛或二手信息。
            - 如果 DB 页面给出具体票价、起价、Super Sparpreis/Sparpreis/Flexpreis 等范围，请原样概括到 fareText。
            - 如果搜索结果只能确认需要在 DB 查询但不能提取金额，fareText 为 null，并在 note 说明。
            - 不要自行估算票价，不要把 Deutschlandticket 覆盖范围当成火车票价。
            - 只输出 JSON，不要多余文字，格式：
              {"fareText": "DB票价/起价/范围或null", "sourceTitle": "DB来源标题或null", "sourceURL": "DB URL或null", "note": "一句中文说明"}
            """
        case .en:
            system = """
            You are the "CityDrive-Ride" German rail-fare lookup assistant. Search Deutsche Bahn / DB official pages (bahn.de or int.bahn.de) for possible rail fares for this route.
            Strict rules:
            - Prefer DB / bahn.de / int.bahn.de connection-search, fare, or booking-result pages; do not use forums or second-hand sources.
            - If a DB page shows a concrete fare, from-price, or Super Sparpreis/Sparpreis/Flexpreis range, summarize it verbatim in fareText.
            - If the result only confirms the fare must be checked on DB but no amount can be extracted, fareText must be null and note should explain.
            - Do not estimate fares yourself, and do not treat Deutschlandticket coverage as a rail fare.
            - Output JSON only, no extra text:
              {"fareText": "DB fare/from-price/range or null", "sourceTitle": "DB source title or null", "sourceURL": "DB URL or null", "note": "one-sentence note in English"}
            """
        }

        let user = lang == .zh
            ? "出发地：\(originText)\n目的地：\(destinationText)\n路线摘要：\(routeText)\n请搜索 DB 官方网站并提取火车票价证据。"
            : "Origin: \(originText)\nDestination: \(destinationText)\nRoute summary: \(routeText)\nSearch DB official websites and extract rail-fare evidence."

        let raw = try? await withTimeout(seconds: 12) {
            try await chat(system: system, user: user, settings: settings, enableSearch: true)
        }
        guard let raw else { return nil }
        return Self.decodeJSON(RailFareEstimate.self, from: raw)
    }

    /// 每次规划前，让 Agent 联网查询用户所选德国票种在本次路线中的适用范围。
    ///
    /// 返回的是决策前提，不作为价格真值，也不直接改动候选方案数字。
    func transitTicketCoveragePremise(originText: String,
                                      destinationText: String,
                                      ticketName: String,
                                      routeText: String,
                                      lang: Lang,
                                      settings: AISettings) async -> String? {
        guard settings.isUsable else { return nil }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「CityDrive-Ride」德国公共交通票种适用范围检索助手。请联网搜索官方或权威信息，判断用户选择的德国常见票种在本次路线中大致是否适用。
            只关注适用范围，不要查询或输出价格。
            要求：
            - 优先判断是否覆盖本地公交、U-Bahn、S-Bahn、Tram、Regionalbahn/RE/RB，以及是否排除 ICE/IC/EC 等长途列车。
            - 对本地/区域月票或优惠票，说明通常需要匹配具体 Verkehrsverbund、票区/环区/城市；如果目的地信息不足，明确写“不确定”。
            - 结论必须是「看起来适用」「看起来不适用」「不确定」之一，并给 1-3 条简短依据。
            - 不编造；搜不到就写不确定并建议以官方票务说明为准。
            """
        case .en:
            system = """
            You are the "CityDrive-Ride" German transit-ticket coverage checker. Search official or authoritative sources and judge whether the selected common German pass appears applicable to this route.
            Focus only on coverage; do not look up or output prices.
            Rules:
            - Prioritize whether local buses, U-Bahn, S-Bahn, trams, Regionalbahn/RE/RB are covered, and whether ICE/IC/EC long-distance trains are excluded.
            - For local/regional monthly or discount passes, explain that the Verkehrsverbund, fare zones/rings/city usually must match; say "uncertain" when the destination details are insufficient.
            - The conclusion must be one of: "appears covered", "appears not covered", or "uncertain", with 1-3 brief reasons.
            - Do not fabricate; if not found, say uncertain and advise checking the official ticket terms.
            """
        }

        let user = lang == .zh
            ? "出发地：\(originText)\n目的地：\(destinationText)\n用户选择票种：\(ticketName)\n路线/候选摘要：\(routeText)"
            : "Origin: \(originText)\nDestination: \(destinationText)\nSelected ticket: \(ticketName)\nRoute/candidate summary: \(routeText)"

        return try? await withTimeout(seconds: 12) {
            try await chat(system: system, user: user, settings: settings, enableSearch: true)
        }
    }

    /// 让 Agent 联网搜索目的地城市/区域的德国常见票种适用范围，并结合用户通勤给出选择建议。
    ///
    /// 失败 / 未启用返回 nil。
    func transitCardAdvice(regionText: String,
                           originText: String,
                           destinationText: String,
                           currencyCode: String,
                           currentCard: String,
                           usageText: String,
                           frequencyText: String,
                           lang: Lang,
                           settings: AISettings) async throws -> String {
        guard settings.isUsable else { throw AIError.notConfigured }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「CityDrive-Ride」德国公共交通票种顾问。请联网搜索这条路线起终点之间相关的**官方或权威票务说明**，重点分析沿途州/区域的火车联票/州票、Deutschlandticket、本地/区域月票、Jobticket、学生票/优惠票等的适用范围，并结合用户使用频率给出选择建议。
            要求：
            1. 先根据起点、终点和路线文字判断可能涉及的德国州、Verkehrsverbund/区域；不确定就写“不确定”。
            2. 联网搜索并分别说明：Deutschlandticket、相关州票/区域火车联票、本地/区域月票、Jobticket/学生票/优惠票可能覆盖哪些交通方式/区域，尤其说明 ICE/IC/EC 等长途列车限制。
            3. 结合用户使用频率判断：高频通勤、每周低频、每月几次、偶尔出行分别更该优先考虑哪类票。
            4. 不编造；如果无法确认沿途州或票区，明确建议以官方 DB / Verkehrsverbund / 州票页面为准。
            5. 不做具体价格或回本计算；简洁、分点、用简体中文输出。
            """
        case .en:
            system = """
            You are the "CityDrive-Ride" German transit-ticket advisor. Search official or authoritative ticket \
            information for the route corridor between the origin and destination, focusing on relevant German \
            federal-state/regional rail passes, the Deutschlandticket, local/regional monthly passes, Jobticket, \
            student/discount passes, etc.
            Rules:
            1. First infer the likely German federal states, Verkehrsverbund areas, or regional fare zones involved; if uncertain, say so.
            2. Search and compare coverage for the Deutschlandticket, relevant state/regional rail passes, local/regional monthly passes, Jobticket/student/discount passes, especially ICE/IC/EC long-distance train exclusions.
            3. Use the user's frequency to recommend what to consider first for high-frequency commuting, weekly low-frequency use, monthly occasional use, or tourism.
            4. Do not fabricate; if the corridor or fare zones cannot be confirmed, advise checking official DB / Verkehrsverbund / state-ticket pages.
            5. Do not output exact prices or break-even calculations. Be concise and use bullets in English.
            """
        }

        let user = lang == .zh
            ? "路线：\(regionText)\n出发地：\(originText)\n目的地：\(destinationText)\n货币：\(currencyCode)\n我当前的交通卡：\(currentCard)\n使用频率：\(frequencyText)\n出行/路线情况：\(usageText)"
            : "Route: \(regionText)\nOrigin: \(originText)\nDestination: \(destinationText)\nCurrency: \(currencyCode)\nMy current card: \(currentCard)\nFrequency: \(frequencyText)\nTrip/route context: \(usageText)"

        return try await withTimeout(seconds: 15) {
            try await chat(system: system, user: user, settings: settings, enableSearch: true)
        }
    }

    // MARK: - OpenAI 兼容请求

    private func withTimeout<T: Sendable>(seconds: TimeInterval,
                                          _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw AIError.timeout
            }

            guard let result = try await group.next() else { throw AIError.emptyResponse }
            group.cancelAll()
            return result
        }
    }

    private func chat(system: String, user: String, settings: AISettings,
                      enableSearch: Bool = false) async throws -> String {
        guard settings.isUsable else { throw AIError.notConfigured }
        guard let url = URL(string: settings.compatibleChatBaseURL + "/chat/completions") else {
            throw AIError.badURL
        }

        // 联网搜索：Qwen(DashScope) 用 enable_search 开关即可；
        // OpenAI 的 chat/completions 需改用具备内置联网的 *-search-preview 模型。
        let usingOpenAISearch = enableSearch && settings.provider == .openAI
        var model = settings.effectiveModel
        if usingOpenAISearch, settings.customModel.trimmingCharacters(in: .whitespaces).isEmpty {
            model = "gpt-4o-search-preview"
        }
        let qwenSearch: Bool? = (enableSearch && settings.provider == .qwen) ? true : nil

        // GPT-5 / o 系列（推理模型）与 search-preview 不接受自定义 temperature，需省略。
        let lower = model.lowercased()
        let omitsTemperature = lower.hasPrefix("gpt-5") || lower.contains("search-preview")
            || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4")
        let temperature: Double? = omitsTemperature ? nil : 0.4

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = enableSearch ? 18 : 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: temperature,
            enableSearch: qwenSearch
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.server(status: http.statusCode, message: Self.serverMessage(from: data))
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else { throw AIError.emptyResponse }
        return content
    }

    /// 从 OpenAI / DashScope 错误响应中提取可读信息。
    static func serverMessage(from data: Data) -> String {
        struct ErrBody: Decodable {
            struct Err: Decodable { let message: String? }
            let error: Err?
            let message: String?   // 部分网关把 message 放在顶层
        }
        if let body = try? JSONDecoder().decode(ErrBody.self, from: data) {
            if let m = body.error?.message, !m.isEmpty { return m }
            if let m = body.message, !m.isEmpty { return m }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false ? raw! : tr("无错误详情", "no error detail"))
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        /// Qwen / DashScope 联网搜索开关（OpenAI 不传，避免未知参数报错）。
        let enableSearch: Bool?
        struct Message: Encodable { let role: String; let content: String }

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case enableSearch = "enable_search"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(messages, forKey: .messages)
            try c.encodeIfPresent(temperature, forKey: .temperature)
            try c.encodeIfPresent(enableSearch, forKey: .enableSearch)
        }
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String? }
    }
}
