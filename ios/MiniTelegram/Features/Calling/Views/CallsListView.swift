import SwiftUI

public struct CallsListView: View {
    @ObservedObject private var callManager = CallManager.shared
    @State private var callHistory: [CallItem] = []
    @State private var isLoading: Bool = false
    @State private var isShowingNewCallSheet: Bool = false
    @State private var teamMembers: [TeamMember] = []

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            Group {
                if callHistory.isEmpty && !isLoading {
                    emptyCallsView
                } else {
                    List {
                        ForEach(callHistory) { item in
                            CallRowView(item: item) {
                                Task {
                                    await callManager.startCall(
                                        conversationId: item.conversationId,
                                        title: item.conversationTitle,
                                        callType: item.callType
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }

            // In-app floating incoming call banner
            if let incoming = callManager.incomingCallItem {
                IncomingCallBannerView(
                    callItem: incoming,
                    onAccept: {
                        Task {
                            await callManager.answerCall(callItem: incoming)
                        }
                    },
                    onDecline: {
                        Task {
                            await callManager.declineIncomingCall(callId: incoming.id)
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: callManager.incomingCallItem != nil)
                .zIndex(100)
            }
        }
        .navigationTitle(L("tab_calls"))
        .refreshable {
            await fetchCallHistory()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isShowingNewCallSheet = true }) {
                    Image(systemName: "phone.badge.plus")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { callManager.activeCall != nil },
            set: { _ in }
        )) {
            ActiveCallView()
        }
        .sheet(isPresented: $isShowingNewCallSheet) {
            newCallSheet
        }
        .task {
            await fetchCallHistory()
        }
    }

    private var emptyCallsView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            Image(systemName: "phone.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(AppColors.accent.opacity(0.8))

            Text("No Recent Calls")
                .font(AppTypography.title)
                .foregroundColor(AppColors.textPrimary)

            Text("Start crystal-clear audio and video calls with team members protected by WebRTC FrameCryptor E2EE.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            Button(action: { isShowingNewCallSheet = true }) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "phone.fill")
                    Text("Start a Call")
                        .font(AppTypography.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accent)
                .cornerRadius(AppCornerRadius.md)
            }
            .padding(.top, AppSpacing.sm)

            Spacer()
        }
        .padding()
    }

    private var newCallSheet: some View {
        NavigationStack {
            List(teamMembers) { member in
                HStack(spacing: AppSpacing.sm) {
                    AvatarView(name: member.title, avatarUrl: member.avatarUrl, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.title)
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.textPrimary)

                        Text("@\(member.username)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Audio Call Button
                    Button(action: {
                        isShowingNewCallSheet = false
                        Task {
                            await callManager.startCall(
                                conversationId: member.id,
                                title: member.title,
                                callType: .audio
                            )
                        }
                    }) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 36, height: 36)
                            .background(AppColors.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Video Call Button
                    Button(action: {
                        isShowingNewCallSheet = false
                        Task {
                            await callManager.startCall(
                                conversationId: member.id,
                                title: member.title,
                                callType: .video
                            )
                        }
                    }) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 36, height: 36)
                            .background(AppColors.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("New Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action_cancel")) {
                        isShowingNewCallSheet = false
                    }
                }
            }
            .task {
                await fetchTeam()
            }
        }
    }

    private func fetchCallHistory() async {
        isLoading = true

        struct CallHistoryDTO: Codable {
            let id: String
            let conversation_id: String
            let conversation_title: String?
            let conversation_type: String?
            let initiated_by_username: String?
            let initiated_by_display_name: String?
            let call_type: String
            let status: String
            let started_at: String
            let ended_at: String?
            let duration_seconds: Int?
            let is_outgoing: Bool
        }

        do {
            let res: [CallHistoryDTO] = try await APIClient.shared.request(
                endpoint: "/calls/history",
                method: "GET",
                requiresAuth: true
            )

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            self.callHistory = res.map { dto in
                let title = dto.conversation_title ?? (dto.initiated_by_display_name ?? dto.initiated_by_username ?? "Call")
                let caller = dto.initiated_by_display_name ?? dto.initiated_by_username ?? "Team Member"
                let cType: CallType = dto.call_type == "video" ? .video : .audio
                let sDate = dateFormatter.date(from: dto.started_at) ?? Date()
                let eDate = dto.ended_at != nil ? dateFormatter.date(from: dto.ended_at!) : nil

                return CallItem(
                    id: dto.id,
                    conversationId: dto.conversation_id,
                    conversationTitle: title,
                    callerUserId: "",
                    callerName: caller,
                    callType: cType,
                    status: dto.status,
                    startedAt: sDate,
                    endedAt: eDate,
                    durationSeconds: dto.duration_seconds ?? 0,
                    isOutgoing: dto.is_outgoing
                )
            }
            isLoading = false
        } catch {
            isLoading = false
            print("[CallsListView] fetchCallHistory error: \(error.localizedDescription)")
        }
    }

    private func fetchTeam() async {
        do {
            let members: [TeamMember] = try await APIClient.shared.request(
                endpoint: "/auth/team",
                method: "GET",
                requiresAuth: true
            )
            self.teamMembers = members
        } catch {
            print("[CallsListView] fetchTeam error: \(error.localizedDescription)")
        }
    }
}

public struct CallRowView: View {
    public let item: CallItem
    public let onRedial: () -> Void

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            AvatarView(name: item.conversationTitle, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.conversationTitle)
                    .font(AppTypography.headline)
                    .foregroundColor(item.status == "missed" ? AppColors.statusError : AppColors.textPrimary)

                HStack(spacing: 4) {
                    callDirectionIcon

                    Text(formatDate(item.startedAt))
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)

                    if item.durationSeconds > 0 {
                        Text("• \(formatDuration(item.durationSeconds))")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            Spacer()

            Button(action: onRedial) {
                Image(systemName: item.callType == .video ? "video.fill" : "phone.fill")
                    .foregroundColor(AppColors.accent)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(AppColors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var callDirectionIcon: some View {
        if item.isOutgoing {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.statusOnline)
        } else if item.status == "missed" {
            Image(systemName: "phone.arrow.down.left.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.statusError)
        } else {
            Image(systemName: "arrow.down.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.accent)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ duration: Int) -> String {
        let mins = duration / 60
        let secs = duration % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}
