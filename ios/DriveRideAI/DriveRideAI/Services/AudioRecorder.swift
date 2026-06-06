import AVFoundation

/// 麦克风录音（16 kHz WAV，供 Qwen ASR 使用）。
@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func requestPermissionIfNeeded() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            permissionDenied = true
            return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                session.requestRecordPermission { granted in
                    Task { @MainActor in
                        self.permissionDenied = !granted
                        cont.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        guard recorder?.record() == true else {
            throw NSError(domain: "AudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: tr("无法开始录音。", "Couldn't start recording.")])
        }
        fileURL = url
        isRecording = true
    }

    /// 停止录音并返回 WAV 文件 URL。
    func stop() -> URL? {
        guard isRecording else { return nil }
        recorder?.stop()
        isRecording = false
        let url = fileURL
        recorder = nil
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    /// 0…1，用于波形动画。
    var level: Float {
        guard isRecording, let recorder else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (power + 50) / 50))
        return normalized
    }
}
