import SwiftUI

/// 底部需求输入栏。
struct InputBarView: View {
    @Binding var text: String
    var isProcessing: Bool
    var placeholder: String = "描述你的出行需求…"
    var sendIcon: String = "arrow.up"
    var voicePhase: VoiceInteractionManager.Phase = .idle
    var voiceTranscript: String = ""
    var voiceMeterLevel: Float = 0
    var onSend: () -> Void
    var onVoiceTap: (() -> Void)?
    var onDismissVoiceError: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        // 允许在仅填写了起终点、未输入额外需求时也能触发规划。
        !isProcessing && !isVoiceBusy
    }

    private var isRecording: Bool {
        voicePhase == .recording
    }

    private var isVoiceBusy: Bool {
        switch voicePhase {
        case .idle, .error:
            return false
        default:
            return true
        }
    }

    private var voiceButtonDisabled: Bool {
        switch voicePhase {
        case .recognizing, .planning:
            return true
        default:
            return false
        }
    }

    private var showsVoiceStatus: Bool {
        voicePhase != .idle
    }

    private var voiceIcon: String {
        switch voicePhase {
        case .recording:
            return "stop.fill"
        case .recognizing, .planning:
            return "waveform"
        case .speaking:
            return "speaker.wave.2.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "mic.fill"
        }
    }

    private var voiceTint: Color {
        switch voicePhase {
        case .recording, .error:
            return .red
        case .speaking:
            return .green
        default:
            return .accentColor
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsVoiceStatus {
                voiceStatusView
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    if let onVoiceTap {
                        Button(action: onVoiceTap) {
                            Image(systemName: voiceIcon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(voiceTint)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(voiceTint.opacity(isRecording ? 0.16 : 0.1)))
                                .overlay(
                                    Circle()
                                        .strokeBorder(voiceTint.opacity(isRecording ? 0.9 : 0), lineWidth: 1.5)
                                        .scaleEffect(isRecording ? 1 + CGFloat(voiceMeterLevel) * 0.22 : 1)
                                        .animation(.easeOut(duration: 0.08), value: voiceMeterLevel)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(voiceButtonDisabled)
                        .accessibilityLabel(tr("语音输入", "Voice input"))
                    }

                    TextField(placeholder, text: $text, axis: .vertical)
                        .focused($isFocused)
                        .lineLimit(1...4)
                        .font(.body)
                        .submitLabel(.send)
                        .onSubmit { if canSend { onSend() } }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(isRecording ? Color.red.opacity(0.45) : Color.clear, lineWidth: 1)
                )

                Button(action: onSend) {
                    Image(systemName: isProcessing ? "ellipsis" : sendIcon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle().fill(canSend ? Color.accentColor : Color.gray.opacity(0.4))
                        )
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var voiceStatusView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: voiceIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(voiceTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(voicePhase.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(voiceTint)
                    .lineLimit(2)

                if !voiceTranscript.isEmpty {
                    Text(voiceTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if case .error = voicePhase, let onDismissVoiceError {
                Button(action: onDismissVoiceError) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("关闭语音错误", "Dismiss voice error"))
            } else if isVoiceBusy && !isRecording {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(voiceTint.opacity(0.1))
        )
    }
}

#Preview {
    InputBarView(text: .constant(""), isProcessing: false, onSend: {}, onVoiceTap: {})
}
