import SwiftUI

/// Ultra-refined, modern clean luxury in-app alert banner.
/// Crafted with dark obsidian glassmorphism, hairline platinum borders,
/// pure vector SF Symbols, and zero emojis.
public struct LuxuryAlertBannerView: View {
    @ObservedObject private var alertManager = LuxuryAlertManager.shared
    @ObservedObject private var callManager = CallManager.shared

    @State private var dragY: CGFloat = 0

    public init() {}

    public var body: some View {
        Group {
            if let alert = alertManager.currentAlert {
                VStack(spacing: 0) {
                    bannerContent(alert)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.35),
                                                    Color.white.opacity(0.08),
                                                    Color.black.opacity(0.4)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
                        }
                        .padding(.horizontal, 14)
                        .offset(y: dragY)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    if val.translation.height < 0 {
                                        dragY = val.translation.height
                                    }
                                }
                                .onEnded { val in
                                    if val.translation.height < -25 {
                                        alertManager.dismissAlert()
                                    }
                                    withAnimation(.spring()) {
                                        dragY = 0
                                    }
                                }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .padding(.top, 8)
                .ignoresSafeArea(edges: .top)
                .zIndex(9999)
            }
        }
    }

    @ViewBuilder
    private func bannerContent(_ alert: LuxuryAlertItem) -> some View {
        switch alert.type {
        case .incomingCall(let callerName, let callId, let convId, let callType, let avatarUrl, let borderTemplate):
            HStack(spacing: 12) {
                AvatarView(
                    name: callerName,
                    avatarUrl: avatarUrl,
                    size: 44,
                    borderTemplate: borderTemplate
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(callerName)
                        .font(AppTypography.headline)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: callType == "video" ? "video.fill" : "phone.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(callType == "video" ? "Incoming Video Call" : "Incoming Voice Call")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(Color(red: 0.96, green: 0.90, blue: 0.72))
                }

                Spacer(minLength: 8)

                // Decline button
                Button {
                    alertManager.dismissAlert()
                    Task { await callManager.declineIncomingCall(callId: callId) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.85, green: 0.25, blue: 0.25))
                            .frame(width: 38, height: 38)
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                .buttonStyle(.plain)

                // Accept button
                Button {
                    alertManager.dismissAlert()
                    let callItem = CallItem(
                        id: callId,
                        conversationId: convId,
                        conversationTitle: callerName,
                        callerUserId: "",
                        callerName: callerName,
                        callType: callType == "video" ? .video : .audio,
                        status: "ringing",
                        isOutgoing: false
                    )
                    Task { await callManager.answerCall(callItem: callItem) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.75, blue: 0.40))
                            .frame(width: 38, height: 38)
                        Image(systemName: callType == "video" ? "video.fill" : "phone.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                .buttonStyle(.plain)
            }

        case .missedCall(let callerName, let callerUserId, let convId, let callType, let time):
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.65, blue: 0.25).opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "phone.arrow.down.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.35))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Missed Call")
                            .font(AppTypography.headline)
                            .foregroundStyle(Color.white)
                        Text(time)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }

                    Text("\(callerName) tried to call you")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !convId.isEmpty {
                    Button {
                        alertManager.dismissAlert()
                        Task {
                            await callManager.startCall(
                                conversationId: convId,
                                title: callerName,
                                callType: callType == "video" ? .video : .audio
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Call Back")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.20, green: 0.75, blue: 0.40), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    alertManager.dismissAlert()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

        case .friendAlert(let name, let username, let avatarUrl, let borderTemplate, let isSender):
            HStack(spacing: 12) {
                AvatarView(
                    name: name,
                    avatarUrl: avatarUrl,
                    size: 42,
                    borderTemplate: borderTemplate
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.96, green: 0.90, blue: 0.72))
                        Text(isSender ? "Friend Connected" : "New Friend Added")
                            .font(AppTypography.headline)
                            .foregroundStyle(Color.white)
                    }

                    Text("\(name) (@\(username))")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    alertManager.dismissAlert()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
