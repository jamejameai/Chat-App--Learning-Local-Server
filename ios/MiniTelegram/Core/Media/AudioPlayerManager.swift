import Foundation
import AVFoundation

@MainActor
public final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = AudioPlayerManager()

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var activeMessageId: String? = nil
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var progress: Double = 0.0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    public override init() {
        super.init()
    }

    public func play(url: URL, messageId: String? = nil) {
        if activeMessageId == messageId && audioPlayer != nil {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }

        stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()

            self.audioPlayer = player
            self.activeMessageId = messageId
            self.duration = player.duration
            self.currentTime = 0
            self.progress = 0
            self.isPlaying = true

            startTimer()
        } catch {
            print("[AudioPlayerManager] Failed to start audio playback: \(error)")
            stop()
        }
    }

    public func pause() {
        guard let player = audioPlayer, isPlaying else { return }
        player.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    public func resume() {
        guard let player = audioPlayer, !isPlaying else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    public func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        activeMessageId = nil
        currentTime = 0
        progress = 0
        duration = 0
    }

    public func seek(to newProgress: Double) {
        guard let player = audioPlayer else { return }
        let clamped = max(0.0, min(1.0, newProgress))
        let targetTime = player.duration * clamped
        player.currentTime = targetTime
        self.currentTime = targetTime
        self.progress = clamped
    }

    private func startTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.audioPlayer, self.isPlaying else { return }
                self.currentTime = player.currentTime
                if player.duration > 0 {
                    self.progress = player.currentTime / player.duration
                }
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
