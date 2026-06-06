import Foundation

/// 可选的「LLM 增强」规划器。
///
/// 设计原则：**始终可用**。结构化的成本/时间方案仍由本地引擎计算（可靠、可离线）；
/// 若配置了大语言模型 API Key，则用 LLM 把分析说明写得更自然、更贴心。
/// 未配置时自动回退到纯本地结果，App 依然完整可用。
struct AITripPlanner: TripPlanning {

    /// OpenAI 兼容接口配置。把 Key 填到环境变量或 `Secrets.plist`，避免硬编码。
    struct Configuration {
        var apiKey: String
        var baseURL: URL
        var model: String

        /// 从 Info.plist / 环境变量读取配置；未配置返回 nil。
        static func load() -> Configuration? {
            let env = ProcessInfo.processInfo.environment
            let key = env["OPENAI_API_KEY"]
                ?? (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)
            guard let apiKey = key, !apiKey.isEmpty else { return nil }

            let urlString = env["OPENAI_BASE_URL"]
                ?? (Bundle.main.object(forInfoDictionaryKey: "OPENAI_BASE_URL") as? String)
                ?? "https://api.openai.com/v1/chat/completions"
            let model = env["OPENAI_MODEL"]
                ?? (Bundle.main.object(forInfoDictionaryKey: "OPENAI_MODEL") as? String)
                ?? "gpt-4o-mini"

            guard let url = URL(string: urlString) else { return nil }
            return Configuration(apiKey: apiKey, baseURL: url, model: model)
        }
    }

    private let local = LocalTripPlanner()
    private let configuration: Configuration?
    private let session: URLSession

    init(configuration: Configuration? = Configuration.load(),
         session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    var isLLMEnabled: Bool { configuration != nil }

    func plan(for userText: String) async throws -> TripPlanningResult {
        let base = try await local.plan(for: userText)

        // 没有可展示的方案，或未配置 LLM，直接返回本地结果。
        guard !base.plans.isEmpty, let config = configuration else {
            return base
        }

        do {
            let enhancedText = try await enhanceNarrative(result: base, config: config)
            return TripPlanningResult(
                request: base.request,
                plans: base.plans,
                assistantText: enhancedText
            )
        } catch {
            // 网络/解析失败时静默回退到本地文案，保证体验不中断。
            return base
        }
    }

    // MARK: - LLM 调用

    private func enhanceNarrative(result: TripPlanningResult, config: Configuration) async throws -> String {
        let plansDigest = result.plans.map {
            "\($0.mode.displayName)：\($0.costText)、\($0.durationText)、舒适度\($0.comfortScore)/5、碳排放\($0.carbonText)"
        }.joined(separator: "；")

        let system = "你是一名简洁、专业的中文出行助手。基于给定的方案数据，用 2~4 句话给出贴心的对比建议，不要编造数据，不要使用 Markdown 列表。"
        let user = """
        用户需求：\(result.request.rawText)
        已计算方案：\(plansDigest)
        请给出自然语言总结与推荐。
        """

        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.7
        ]

        var request = URLRequest(url: config.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        return content + "\n\n下面是详细方案对比 👇"
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
