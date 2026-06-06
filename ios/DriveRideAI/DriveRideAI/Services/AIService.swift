import Foundation

/// 后台 AI 服务商。OpenAI 与 Qwen（通义千问）均为 OpenAI 兼容的 Chat Completions 接口，
/// 因此共用一套客户端，仅默认 baseURL / 模型不同。
enum AIProvider: String, Codable, CaseIterable, Identifiable {
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
    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .qwen:   return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .qwen:   return "qwen-plus"
        }
    }
}

/// 后台 AI 设置（可选，默认关闭）。Key 仅保存在本机。
struct AISettings: Codable, Equatable {
    var enabled: Bool = false
    var provider: AIProvider = .qwen
    var apiKey: String = ""
    /// 自定义模型（留空用服务商默认）。
    var customModel: String = ""
    /// 自定义 baseURL（留空用服务商默认）。
    var customBaseURL: String = ""

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

    static let disabled = AISettings()
}

/// 后台 AI 客户端（OpenAI 兼容）。
///
/// 当前仅用于**润色**已经算好的方案文案：保留全部真实数字 / 地名 / 时间 / 价格，
/// 不新增、不编造。未启用或失败时返回 nil，调用方回落到本地文案。
struct AIService {

    /// 把本地生成的文案润色得更自然（同语言）。失败 / 未启用返回 nil。
    func polish(text: String, lang: Lang, settings: AISettings) async -> String? {
        guard settings.isUsable else { return nil }

        let system: String
        switch lang {
        case .zh:
            system = """
            你是「Drive&Ride」通勤出行助手。请把用户给出的方案说明润色得自然、友好、简洁。
            严格要求：必须原样保留所有数字、地名、时间、价格、单位与符号（如「≥」），
            不得新增、删改或编造任何信息；只优化措辞与语气。直接输出润色后的简体中文。
            """
        case .en:
            system = """
            You are the "Drive&Ride" commute assistant. Polish the user's plan summary to be \
            natural, friendly and concise. Strict rules: keep every number, place name, time, \
            price, unit and symbol (e.g. "≥") exactly; do not add, change, or fabricate any \
            information — only improve wording. Output the polished English text directly.
            """
        }

        return try? await chat(system: system, user: text, settings: settings)
    }

    // MARK: - OpenAI 兼容请求

    private func chat(system: String, user: String, settings: AISettings) async throws -> String {
        guard let url = URL(string: settings.effectiveBaseURL + "/chat/completions") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatRequest(
            model: settings.effectiveModel,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: 0.4
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else { throw URLError(.cannotParseResponse) }
        return content
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String? }
    }
}
