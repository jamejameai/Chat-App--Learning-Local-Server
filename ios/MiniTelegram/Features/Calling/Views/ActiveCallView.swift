import SwiftUI

public struct ActiveCallView: View {
    @ObservedObject private var callManager = CallManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingSecurityModal: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Background: Dark gradient for video/call atmosphere
            LinearGradient(
                colors: [Color.black, Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar: Back / Minimize button and E2EE Fingerprint
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // E2EE Security Shield & Emojis
                    if !callManager.verificationFingerprint.isEmpty {
                        Button(action: { isShowingSecurityModal = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(AppColors.statusOnline)
                                    .font(.system(size: 13))

                                Text(callManager.verificationFingerprint)
                                    .font(.system(size: 15))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(AppCornerRadius.full)
                        }
                    }

                    Spacer()

                    // Balance spacer
                    Color.clear
                        .frame(width: 42, height: 42)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)

                Spacer()

                // Center Stage: Avatar or Video Feed
                if callManager.isVideoEnabled {
                    videoStageView
                } else {
                    audioStageView
                }

                Spacer()

                // Bottom Call Controls Bar
                callControlsBar
                    .padding(.bottom, AppSpacing.xl)
            }
        }
        .sheet(isPresented: $isShowingSecurityModal) {
            e2eeExplanationModal
        }
    }

    // MARK: - Audio Stage View
    private var audioStageView: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                // Pulsating aura when ringing or connecting
                if callManager.callState == .dialing || callManager.callState == .connecting {
                    Circle()
                        .fill(AppColors.accent.opacity(0.2))
                        .frame(width: 150, height: 150)
                        .scaleEffect(1.2)
                        .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: callManager.callState)
                }

                AvatarView(name: callManager.activeCall?.conversationTitle ?? "Contact", size: 100)
            }

            VStack(spacing: 6) {
                Text(callManager.activeCall?.conversationTitle ?? "Calling...")
                    .font(AppTypography.title)
                    .foregroundColor(.white)

                Text(statusText())
                    .font(AppTypography.body)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Video Stage View
    private var videoStageView: some View {
        ZStack(alignment: .topTrailing) {
            // Simulated Remote Video Feed
            Rectangle()
                .fill(Color(white: 0.18))
                .cornerRadius(AppCornerRadius.lg)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.white.opacity(0.4))
                        Text(callManager.activeCall?.conversationTitle ?? "Remote Participant")
                            .font(AppTypography.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                )

            // Local Camera Preview Thumbnail (Picture-in-Picture)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.28))
                .frame(width: 100, height: 140)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: callManager.isFrontCamera ? "camera.fill" : "camera.metering.matrix")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                        Text("You")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                )
                .padding(12)
        }
        .frame(maxHeight: 400)
        .padding(.horizontal, AppSpacing.md)
    }

    // MARK: - Controls Bar
    private var callControlsBar: some View {
        HStack(spacing: 24) {
            // Mute Button
            Button(action: { callManager.toggleMute() }) {
                controlCircle(
                    icon: callManager.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: "Mute",
                    isActive: callManager.isMuted
                )
            }

            // Video Button
            Button(action: { callManager.toggleVideo() }) {
                controlCircle(
                    icon: callManager.isVideoEnabled ? "video.fill" : "video.slash.fill",
                    label: "Video",
                    isActive: callManager.isVideoEnabled
                )
            }

            // Flip Camera Button (if video enabled)
            if callManager.isVideoEnabled {
                Button(action: { callManager.flipCamera() }) {
                    controlCircle(
                        icon: "camera.rotate.fill",
                        label: "Flip",
                        isActive: false
                    )
                }
            } else {
                // Speaker Button
                Button(action: { callManager.toggleSpeaker() }) {
                    controlCircle(
                        icon: callManager.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                        label: "Speaker",
                        isActive: callManager.isSpeakerOn
                    )
                }
            }

            // End Call Button
            Button(action: {
                Task {
                    await callManager.endCurrentCall()
                    dismiss()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(AppColors.statusError)
                        .frame(width: 60, height: 60)

                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func controlCircle(icon: String, label: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.white : Color.white.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? .black : .white)
            }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func statusText() -> String {
        switch callManager.callState {
        case .dialing:
            return "Dialing..."
        case .ringing:
            return "Ringing..."
        case .connecting:
            return "Connecting WebRTC SFU..."
        case .connected:
            return formatDuration(callManager.callDuration)
        case .reconnecting:
            return "Reconnecting..."
        case .ended:
            return "Call Ended"
        case .idle:
            return ""
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - E2EE Security Modal
    private var e2eeExplanationModal: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundColor(AppColors.statusOnline)
                    .padding(.top, AppSpacing.lg)

                Text("End-to-End Encrypted")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)

                Text("This call is secured with WebRTC FrameCryptor (SFrame). No intermediary, not even the LiveKit SFU server, has access to the audio or video frames.")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)

                VStack(spacing: 8) {
                    Text("Verification Fingerprint:")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundColor(AppColors.textTertiary)

                    Text(callManager.verificationFingerprint)
                        .font(.system(size: 32))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(AppColors.surface)
                        .cornerRadius(AppCornerRadius.md)

                    Text("Compare these 4 emojis with your peer. If they match, your connection is guaranteed cryptographically authentic.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()

                Button(L("action_close", "Close")) {
                    isShowingSecurityModal = false
                }
                .font(AppTypography.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accent)
                .cornerRadius(AppCornerRadius.md)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
