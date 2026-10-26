import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var callManager = CallManager.shared
    @State private var showBarkSetup = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
                // Feature 1: Telegram-style Chat
                NavigationStack {
                    ConversationListView()
                }
                .tabItem {
                    Label(L("tab_chats"), systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(AppTab.chats)

                // Feature 2: Instagram/Facebook-style Profile & Friends
                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
                .tag(AppTab.profile)

                NavigationStack {
                    LiveLocationView()
                }
                .tabItem {
                    Label("Live", systemImage: "location.north.circle.fill")
                }
                .tag(AppTab.liveLocation)

                // Feature 3: Settings for customize app & profile account
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label(L("tab_settings"), systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
            }
            .tint(AppColors.accent)

            // Luxury Real-time Heads-up Banner for Calls and Friend Alerts
            LuxuryAlertBannerView()
                .zIndex(999)
        }
        // Incoming / active calls appear over any screen
        .fullScreenCover(isPresented: Binding(
            get: { callManager.activeCall != nil },
            set: { _ in }
        )) {
            CallScreen()
        }
        .task {
            // Logged in: keep the live connection open and alert on new messages
            RealtimeService.shared.start()
            MessageAlertManager.shared.start()

            // Once per phone: offer alerts for when the app is closed, which iOS can't do for it
            await BarkRelayManager.shared.refresh()
            if let bark = BarkRelayManager.shared.settings, !bark.configured, !BarkRelayManager.setupPromptShown {
                BarkRelayManager.setupPromptShown = true
                showBarkSetup = true
            }
        }
        .sheet(isPresented: $showBarkSetup) {
            NavigationStack {
                BackgroundNotificationsView(isPrompt: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                RealtimeService.shared.reportAppState() // on screen: the server holds back Bark alerts
                RealtimeService.shared.ensureConnected()
                MessageAlertManager.shared.appDidBecomeActive()
                Task { await BarkRelayManager.shared.refreshSystemPermission() }
            case .background:
                RealtimeService.shared.reportAppState() // off screen: alerts now go through Bark
                MessageAlertManager.shared.appDidEnterBackground()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversationRequested)) { _ in
            appState.selectedTab = .chats // ConversationListView opens the chat itself
        }
    }
}
