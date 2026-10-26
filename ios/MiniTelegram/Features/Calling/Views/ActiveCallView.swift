import SwiftUI
import LiveKit

/// Full-screen call: the other person's video (or their photo for voice calls), my camera preview,
/// status / timer and the call controls.
public struct ActiveCallView: View {
    @ObservedObject private var callManager = CallManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Other person's video, full screen
            if let remote = callManager.remoteVideoTrack {
                SwiftUIVideoView(remote, layoutMode: .fill)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if callManager.remoteVideoTrack == nil {
                    peerIdentity
                        .padding(.top, 80)
                } else {
                    statusPill
                        .padding(.top, AppSpacing.md)
                }

                Spacer()

                if let error = callManager.errorMessage {
                    Text(error)
                        .font(AppTypography.footnote)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
                        .padding(.bottom, AppSpacing.md)
                }

                controls
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, AppSpacing.lg)

            // My camera preview, top-right
            if callManager.isVideoEnabled, let local = callManager.localVideoTrack {
                VStack {
                    HStack {
                        Spacer()
                        SwiftUIVideoView(local, layoutMode: .fill, mirrorMode: callManager.isFrontCamera ? .mirror : .off)
                            .frame(width: 110, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(radius: 8)
                    }
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.trailing, AppSpacing.md)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(callManager.remoteVideoTrack != nil)
    }

    private var title: String {
        callManager.activeCall?.conversationTitle ?? "Call"
    }

    private var peerIdentity: some View {
        VStack(spacing: AppSpacing.md) {
            AvatarView(name: title, size: 110)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isWaiting ? 0.35 : 0), lineWidth: 3)
                        .scaleEffect(isWaiting ? 1.15 : 1)
                        .animation(isWaiting ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isWaiting)
                )

            Text(title)
                .font(AppTypography.title)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(statusText)
                .font(AppTypography.subheadline)
                .foregroundColor(.white.opacity(0.75))
                .monospacedDigit()
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppTypography.subheadline.weight(.semibold))
            Text("·")
            Text(statusText)
                .monospacedDigit()
        }
        .font(AppTypography.footnote)
        .foregroundColor(.white)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
    }

    private var controls: some View {
        HStack(spacing: AppSpacing.lg) {
            CallControlButton(
                icon: callManager.isMuted ? "mic.slash.fill" : "mic.fill",
                isActive: callManager.isMuted
            ) { callManager.toggleMute() }

            CallControlButton(
                icon: callManager.isVideoEnabled ? "video.fill" : "video.slash.fill",
                isActive: !callManager.isVideoEnabled
            ) { callManager.toggleVideo() }

            if callManager.isVideoEnabled {
                CallControlButton(icon: "arrow.triangle.2.circlepath.camera.fill", isActive: false) {
                    callManager.flipCamera()
                }
            } else {
                CallControlButton(
                    icon: callManager.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                    isActive: callManager.isSpeakerOn
                ) { callManager.toggleSpeaker() }
            }

            Button {
                Task { await callManager.endCurrentCall() }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 68, height: 68)
                    .background(AppColors.statusError)
                    .clipShape(Circle())
            }
        }
    }

    private var isWaiting: Bool {
        [.dialing, .ringing, .connecting].contains(callManager.callState)
    }

    private var statusText: String {
        switch callManager.callState {
        case .idle, .dialing: return "Calling…"
        case .ringing: return "Ringing…"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .connected: return formatDuration(callManager.callDuration)
        case .ended: return "Call ended"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Round call-control button (white when active, translucent otherwise).
struct CallControlButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 58, height: 58)
                .background(isActive ? Color.white : Color.white.opacity(0.18))
                .clipShape(Circle())
        }
    }
}

/// Full-screen incoming call with Decline / Accept.
public struct IncomingCallView: View {
    @ObservedObject private var callManager = CallManager.shared
    let call: CallItem

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.accent.opacity(0.9), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                Spacer().frame(height: 80)
                AvatarView(name: call.callerName, size: 120)
                Text(call.callerName)
                    .font(AppTypography.title)
                    .foregroundColor(.white)
                Text(call.callType == .video ? "Incoming video call…" : "Incoming voice call…")
                    .font(AppTypography.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()

                HStack(spacing: 80) {
                    VStack(spacing: 8) {
                        Button {
                            Task { await callManager.declineIncomingCall(callId: call.id) }
                        } label: {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(AppColors.statusError)
                                .clipShape(Circle())
                        }
                        Text("Decline").font(AppTypography.footnote).foregroundColor(.white)
                    }

                    VStack(spacing: 8) {
                        Button {
                            Task { await callManager.answerCall(callItem: call) }
                        } label: {
                            Image(systemName: call.callType == .video ? "video.fill" : "phone.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(AppColors.statusOnline)
                                .clipShape(Circle())
                        }
                        Text("Accept").font(AppTypography.footnote).foregroundColor(.white)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// What MainTabView shows full screen while a call is ringing or in progress.
public struct CallScreen: View {
    @ObservedObject private var callManager = CallManager.shared

    public init() {}

    public var body: some View {
        if callManager.activeCall == nil, let incoming = callManager.incomingCallItem {
            IncomingCallView(call: incoming)
        } else {
            ActiveCallView()
        }
    }
}
