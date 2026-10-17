import Foundation
import AVFoundation

@MainActor
public final class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    public static let shared = AudioRecorderManager()

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var liveWaveform: [Float] = []

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentRecordingURL: URL?

    public override init() {
        super.init()
    }

    public func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func startRecording() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[AudioRecorderManager] Failed to set audio session: \(error)")
            return false
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("voice_\(UUID().uuidString).m4a")
        self.currentRecordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingDuration = 0
            liveWaveform = []

            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                    recorder.updateMeters()
                    self.recordingDuration = recorder.currentTime

                    // Normalize decibels (-60 to 0) to 0.0...1.0 range
                    let power = recorder.averagePower(forChannel: 0)
                    let normalized = max(0.1, min(1.0, (power + 60.0) / 60.0))
                    self.liveWaveform.append(normalized)
                }
            }

            return true
        } catch {
            print("[AudioRecorderManager] Error creating recorder: \(error)")
            return false
        }
    }

    public func stopRecording() -> (fileURL: URL, duration: TimeInterval, waveform: [Float])? {
        meterTimer?.invalidate()
        meterTimer = nil

        guard let recorder = audioRecorder, recorder.isRecording, let url = currentRecordingURL else {
            return nil
        }

        let duration = recorder.currentTime
        recorder.stop()
        isRecording = false

        let finalWaveform = liveWaveform.isEmpty ? [0.5, 0.6, 0.4, 0.7, 0.5] : liveWaveform
        return (url, duration, finalWaveform)
    }

    public func cancelRecording() {
        meterTimer?.invalidate()
        meterTimer = nil

        audioRecorder?.stop()
        isRecording = false

        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
        }
        liveWaveform = []
        recordingDuration = 0
    }
}
