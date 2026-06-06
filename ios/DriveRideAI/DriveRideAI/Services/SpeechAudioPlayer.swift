import AVFoundation

/// 播放 DashScope TTS 返回的远程音频。
@MainActor
final class SpeechAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func play(data: Data) async {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)

            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
            isPlaying = true
            player?.play()

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                finishContinuation = cont
            }
        } catch {
            isPlaying = false
        }
    }

    func play(url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await play(data: data)
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        finishContinuation?.resume()
        finishContinuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.finishContinuation?.resume()
            self.finishContinuation = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
