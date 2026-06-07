import Foundation

/// 语音交互状态机：录音 → Qwen ASR → 规划 → Qwen TTS 朗读。
@MainActor
final class VoiceInteractionManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case recognizing
        case planning
        case speaking
        case error(String)

        var statusText: String {
            switch self {
            case .idle:
                return tr("点按麦克风开始说话", "Tap the mic to speak")
            case .recording:
                return tr("正在听… 再次点按结束", "Listening… tap again to finish")
            case .recognizing:
                return tr("正在识别语音…", "Recognizing speech…")
            case .planning:
                return tr("正在分析出行方案…", "Analyzing your trip…")
            case .speaking:
                return tr("正在朗读回复…", "Speaking the reply…")
            case let .error(msg):
                return msg
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var replyText: String = ""
    @Published private(set) var meterLevel: Float = 0

    private lazy var recorder = AudioRecorder()
    private lazy var player = SpeechAudioPlayer()
    private let speech = DashScopeSpeechService()
    private var meterTask: Task<Void, Never>?

    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool {
        switch phase {
        case .idle, .error: return false
        default: return true
        }
    }

    /// 切换录音：idle/error → 开始；recording → 结束并走 ASR→规划→TTS 全流程。
    func toggleRecording(settings: AISettings,
                         lang: Lang,
                         plan: @escaping (String) async -> String?) async {
        if recorder.isRecording {
            await finishRecording(settings: settings, lang: lang, plan: plan)
        } else {
            await startRecording(settings: settings)
        }
    }

    func stopSpeaking() {
        player.stop()
        if phase == .speaking { phase = .idle }
    }

    func cancelInteraction() {
        stopMeterPolling()
        _ = recorder.stop()
        player.stop()
        transcript = ""
        replyText = ""
        phase = .idle
    }

    func dismissError() {
        if case .error = phase { phase = .idle }
    }

    // MARK: - Private

    private func startRecording(settings: AISettings) async {
        stopSpeaking()
        dismissError()

        guard settings.isUsable, settings.provider == .qwen else {
            phase = .error(DashScopeSpeechService.SpeechError.qwenOnly.localizedDescription ?? "")
            return
        }

        guard await recorder.requestPermissionIfNeeded() else {
            phase = .error(tr("麦克风权限未开启，请在系统设置中允许。",
                               "Microphone access is off — enable it in Settings."))
            return
        }

        do {
            try recorder.start()
            phase = .recording
            startMeterPolling()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func finishRecording(settings: AISettings,
                                 lang: Lang,
                                 plan: @escaping (String) async -> String?) async {
        stopMeterPolling()
        guard let url = recorder.stop() else {
            phase = .idle
            return
        }

        phase = .recognizing
        do {
            let data = try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                return data
            }.value
            guard !data.isEmpty else { throw DashScopeSpeechService.SpeechError.emptyAudio }

            let text = try await speech.recognize(wavData: data, lang: lang, settings: settings)
            transcript = text

            phase = .planning
            guard let reply = await plan(text), !reply.isEmpty else {
                phase = .error(tr("未能生成出行方案，请确认已填写出发地和目的地。",
                                  "Couldn't build a plan — make sure origin and destination are set."))
                return
            }
            replyText = reply

            phase = .speaking
            let audioURL = try await speech.synthesize(text: reply, lang: lang, settings: settings)
            await player.play(url: audioURL)
            phase = .idle
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task {
            while !Task.isCancelled, recorder.isRecording {
                meterLevel = recorder.level
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            meterLevel = 0
        }
    }

    private func stopMeterPolling() {
        meterTask?.cancel()
        meterTask = nil
        meterLevel = 0
    }
}
