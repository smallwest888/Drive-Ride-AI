import SwiftUI

/// 全屏语音交互模式：Qwen ASR 听写 → 规划 → Qwen TTS 朗读。
struct VoiceModeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appLocale: AppLocale
    @ObservedObject var viewModel: PlannerViewModel
    @StateObject private var voice = VoiceInteractionManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                transcriptCard

                micButton

                Text(voice.phase.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if case .error = voice.phase {
                    Button(tr("重试", "Retry")) { voice.dismissError() }
                        .buttonStyle(.bordered)
                }

                Spacer()

                hintFooter
            }
            .padding(.horizontal, 20)
            .navigationTitle(tr("语音模式", "Voice Mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("关闭", "Close")) { dismiss() }
                }
                if voice.phase == .speaking {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(tr("停止朗读", "Stop")) { voice.stopSpeaking() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(voice.isBusy)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !voice.transcript.isEmpty {
                Label(tr("你说", "You said"), systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(voice.transcript)
                    .font(.body)
            }
            if !voice.replyText.isEmpty {
                Divider().padding(.vertical, 4)
                Label(tr("助手回复", "Assistant"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(voice.replyText)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            if voice.transcript.isEmpty && voice.replyText.isEmpty {
                Text(tr("说出你的出行需求，例如「有点赶，想省钱」",
                        "Say your travel needs, e.g. \"a bit rushed, save money\""))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 24, tint: .accentColor, material: .ultraThinMaterial)
        .frame(minHeight: 120)
    }

    private var micButton: some View {
        Button {
            Task {
                let settings = profileStore.profile.ai ?? .disabled
                await voice.toggleRecording(settings: settings, lang: appLocale.lang) { text in
                    await viewModel.submitVoice(text)
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .overlay(Circle().fill((voice.isRecording ? Color.red : Color.accentColor).opacity(0.08)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.9))
                    .shadow(color: (voice.isRecording ? Color.red : Color.accentColor).opacity(0.16),
                            radius: 18, x: 0, y: 8)
                Circle()
                    .stroke(voice.isRecording ? Color.red : Color.accentColor, lineWidth: 3)
                    .frame(width: 96 + CGFloat(voice.meterLevel) * 24,
                           height: 96 + CGFloat(voice.meterLevel) * 24)
                    .animation(.easeOut(duration: 0.08), value: voice.meterLevel)
                Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(voice.isRecording ? .red : Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(voice.isBusy && !voice.isRecording)
    }

    private var hintFooter: some View {
        VStack(spacing: 6) {
            Text(tr("语音由阿里云 Qwen3-ASR + Qwen3-TTS 驱动（海外接入点）",
                    "Powered by Alibaba Qwen3-ASR + Qwen3-TTS (international endpoint)"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(tr("请先在设置中开启后台 AI 并选择 Qwen 服务商",
                    "Enable Background AI with Qwen as the provider in Settings first"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.bottom, 12)
    }
}
