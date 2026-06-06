import Foundation

/// 阿里云 DashScope 语音服务（海外新加坡接入点）：Qwen3-ASR-Flash + Qwen3-TTS-Flash。
struct DashScopeSpeechService {

    enum SpeechError: LocalizedError {
        case qwenOnly
        case notConfigured
        case emptyAudio
        case emptyText
        case badResponse

        var errorDescription: String? {
            switch self {
            case .qwenOnly:
                return tr("语音功能仅支持 Qwen（通义千问），请在设置里把服务商改为 Qwen。",
                          "Voice features require Qwen — switch the provider to Qwen in Settings.")
            case .notConfigured:
                return tr("请先在 设置 → 后台 AI 中开启并填入 Qwen API Key。",
                          "Enable Background AI and add your Qwen API key in Settings first.")
            case .emptyAudio:
                return tr("录音为空，请重新说一遍。", "Recording was empty — please try again.")
            case .emptyText:
                return tr("没有可朗读的内容。", "Nothing to speak.")
            case .badResponse:
                return tr("语音服务返回异常。", "Unexpected response from the speech service.")
            }
        }
    }

    // MARK: - ASR（Qwen3-ASR-Flash，OpenAI 兼容 + Base64 音频）

    func recognize(wavData: Data, lang: Lang, settings: AISettings) async throws -> String {
        try validateQwen(settings)

        let base64 = wavData.base64EncodedString()
        let dataURI = "data:audio/wav;base64,\(base64)"

        struct ASRRequest: Encodable {
            struct Message: Encodable {
                struct Part: Encodable {
                    struct InputAudio: Encodable { let data: String }
                    let type: String
                    let input_audio: InputAudio
                }
                let role: String
                let content: [Part]
            }
            struct ASROptions: Encodable {
                let enable_itn: Bool
                let language: String?
            }
            let model: String
            let messages: [Message]
            let stream: Bool
            let asr_options: ASROptions
        }

        let body = ASRRequest(
            model: "qwen3-asr-flash",
            messages: [
                .init(role: "user", content: [
                    .init(type: "input_audio", input_audio: .init(data: dataURI))
                ])
            ],
            stream: false,
            asr_options: .init(enable_itn: true, language: lang == .zh ? "zh" : "en")
        )

        let url = URL(string: settings.compatibleChatBaseURL + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpeechError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.server(status: http.statusCode, message: AIService.serverMessage(from: data))
        }

        struct ASRResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(ASRResponse.self, from: data)
        let text = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw SpeechError.emptyAudio }
        return text
    }

    // MARK: - TTS（Qwen3-TTS-Flash，返回 24h 有效音频 URL）

    func synthesize(text: String, lang: Lang, settings: AISettings) async throws -> URL {
        try validateQwen(settings)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpeechError.emptyText }

        // 朗读过长回复时截断，避免 TTS 超时。
        let speakText = trimmed.count > 900 ? String(trimmed.prefix(900)) + "…" : trimmed

        struct TTSRequest: Encodable {
            struct Input: Encodable {
                let text: String
                let voice: String
                let language_type: String
            }
            let model: String
            let input: Input
        }

        let voice = settings.ttsVoice.trimmingCharacters(in: .whitespaces).isEmpty ? "Cherry" : settings.ttsVoice
        let body = TTSRequest(
            model: "qwen3-tts-flash",
            input: .init(
                text: speakText,
                voice: voice,
                language_type: lang == .zh ? "Chinese" : "English"
            )
        )

        let url = URL(string: settings.dashScopeAPIRoot + "/services/aigc/multimodal-generation/generation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpeechError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.server(status: http.statusCode, message: AIService.serverMessage(from: data))
        }

        struct TTSResponse: Decodable {
            struct Output: Decodable {
                struct Audio: Decodable { let url: String? }
                let audio: Audio?
            }
            let output: Output?
        }
        let decoded = try JSONDecoder().decode(TTSResponse.self, from: data)
        guard let urlString = decoded.output?.audio?.url, let audioURL = URL(string: urlString) else {
            throw SpeechError.badResponse
        }
        return audioURL
    }

    private func validateQwen(_ settings: AISettings) throws {
        guard settings.isUsable else { throw SpeechError.notConfigured }
        guard settings.provider == .qwen else { throw SpeechError.qwenOnly }
    }
}
