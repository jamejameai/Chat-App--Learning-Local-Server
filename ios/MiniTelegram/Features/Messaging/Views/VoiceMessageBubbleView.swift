import SwiftUI

public struct VoiceMessageBubbleView: View {
    public let messageId: String
    public let isOutgoing: Bool
    public let voiceNote: VoiceNoteMetadata
    public let attachment: MessageAttachment?

    @StateObject private var player = AudioPlayerManager.shared
    @Environment(\.chatTheme) private var theme
    @State private var isLoadingAudio: Bool = false
    @State private var localAudioUrl: URL? = nil

    public init(
        messageId: String,
        isOutgoing: Bool,
        voiceNote: VoiceNoteMetadata,
        attachment: MessageAttachment?
    ) {
        self.messageId = messageId
        self.isOutgoing = isOutgoing
        self.voiceNote = voiceNote
        self.attachment = attachment
    }

    private var isCurrentlyPlaying: Bool {
        player.activeMessageId == messageId && player.isPlaying
    }

    private var activeProgress: Double {
        if player.activeMessageId == messageId {
            return player.progress
        }
        return 0.0
    }

    public var body: some View {
        HStack(spacing: AppSpacing.xs) {
            // Play/Pause/Loading Button
            Button(action: handlePlayTap) {
                ZStack {
                    Circle()
                        .fill(isOutgoing ? theme.outgoingText : theme.accent)
                        .frame(width: 38, height: 38)

                    if isLoadingAudio {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isOutgoing ? (theme.outgoing.first ?? theme.accent) : Color.white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isOutgoing ? (theme.outgoing.first ?? theme.accent) : Color.white)
                            .offset(x: isCurrentlyPlaying ? 0 : 1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Waveform and Duration
            VStack(alignment: .leading, spacing: 4) {
                // Waveform Bars
                GeometryReader { geometry in
                    let samples = voiceNote.waveformSamples.isEmpty ? [0.4, 0.6, 0.3, 0.7, 0.5, 0.8, 0.4] : voiceNote.waveformSamples
                    let barWidth: CGFloat = 2.5
                    let spacing: CGFloat = 2.0
                    let totalBarWidth = barWidth + spacing
                    let maxBars = max(1, Int(geometry.size.width / totalBarWidth))
                    let visibleSamples = downsample(samples: samples, targetCount: maxBars)

                    HStack(alignment: .center, spacing: spacing) {
                        ForEach(0..<visibleSamples.count, id: \.self) { index in
                            let sample = visibleSamples[index]
                            let normalizedHeight = max(4.0, CGFloat(sample) * geometry.size.height)
                            let barFraction = Double(index) / Double(visibleSamples.count)
                            let isPlayed = barFraction <= activeProgress

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(barColor(isPlayed: isPlayed))
                                .frame(width: barWidth, height: normalizedHeight)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = max(0.0, min(1.0, Double(value.location.x / geometry.size.width)))
                                if player.activeMessageId == messageId {
                                    player.seek(to: progress)
                                }
                            }
                    )
                }
                .frame(height: 26)

                // Duration Label
                Text(formatDuration())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isOutgoing ? theme.outgoingMeta : theme.incomingMeta)
            }
        }
        .frame(minWidth: 180, maxWidth: 220)
        .padding(.vertical, 4)
        .onAppear {
            resolveLocalAudio()
        }
    }

    private func barColor(isPlayed: Bool) -> Color {
        if isOutgoing {
            return isPlayed ? Color.white : Color.white.opacity(0.4)
        } else {
            return isPlayed ? theme.accent : theme.accent.opacity(0.3)
        }
    }

    private func formatDuration() -> String {
        if player.activeMessageId == messageId && player.isPlaying {
            let current = Int(player.currentTime)
            let mins = current / 60
            let secs = current % 60
            return String(format: "%d:%02d", mins, secs)
        } else {
            let total = Int(voiceNote.durationSeconds)
            let mins = total / 60
            let secs = total % 60
            return String(format: "%d:%02d", mins, secs)
        }
    }

    private func handlePlayTap() {
        if isCurrentlyPlaying {
            player.pause()
            return
        }

        if player.activeMessageId == messageId {
            player.resume()
            return
        }

        if let localUrl = localAudioUrl, FileManager.default.fileExists(atPath: localUrl.path) {
            player.play(url: localUrl, messageId: messageId)
            return
        }

        guard let attachment = attachment else { return }

        isLoadingAudio = true
        Task {
            do {
                let decryptedUrl = try await AttachmentManager.shared.downloadAndDecryptAttachment(attachment: attachment)
                await MainActor.run {
                    self.localAudioUrl = decryptedUrl
                    self.isLoadingAudio = false
                    self.player.play(url: decryptedUrl, messageId: messageId)
                }
            } catch {
                await MainActor.run {
                    self.isLoadingAudio = false
                }
                print("[VoiceMessageBubbleView] Failed to download audio: \(error)")
            }
        }
    }

    private func resolveLocalAudio() {
        if let path = attachment?.localDecryptedPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                self.localAudioUrl = url
            }
        }
    }

    private func downsample(samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard samples.count > targetCount else { return samples }

        var result: [Float] = []
        let chunkSize = Double(samples.count) / Double(targetCount)

        for i in 0..<targetCount {
            let start = Int(Double(i) * chunkSize)
            let end = min(samples.count, Int(Double(i + 1) * chunkSize))
            if start < end {
                let chunk = samples[start..<end]
                let avg = chunk.reduce(0, +) / Float(chunk.count)
                result.append(avg)
            } else if start < samples.count {
                result.append(samples[start])
            }
        }

        return result
    }
}
