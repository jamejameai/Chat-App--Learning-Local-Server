import SwiftUI

@main
struct MiniTelegramApp: App {
    // Resumes the saved session: the user logs in once and stays logged in until they log out
    @StateObject private var appState = AppState(restoreSession: true)
    @StateObject private var appContainer = AppContainer.shared
    @StateObject private var localization = LocalizationManager.shared
    @AppStorage("live_location_permission_intro_seen") private var hasSeenLocationIntro = false
    @State private var showingLocationIntro = false

    init() {
        // Both must be set up before launch finishes: a notification tap that launches the app is
        // delivered to this delegate, and iOS only runs background refresh tasks registered here.
        _ = PushNotificationManager.shared
        BackgroundSyncManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    MainTabView()
                } else {
                    WelcomeView()
                }
            }
            .environmentObject(appState)
            .environmentObject(appContainer)
            .environmentObject(localization)
            .preferredColorScheme(.light) // Default to clean white interface as specified
            // Tapping a Bark alert opens ourchat://chat/<conversation id>
            .onOpenURL { url in
                guard url.scheme == "ourchat", url.host == "chat",
                      let conversationId = url.pathComponents.dropFirst().first, !conversationId.isEmpty else { return }
                // Kept until the chat list exists (e.g. still on the login screen)
                MessageAlertManager.shared.pendingConversationId = conversationId
                NotificationCenter.default.post(name: .openConversationRequested, object: conversationId)
            }
            .task {
                Task { await LiveLocationViewModel.shared.retryPendingRevocation() }
                guard !hasSeenLocationIntro else { return }
                hasSeenLocationIntro = true
                showingLocationIntro = true
            }
            .sheet(isPresented: $showingLocationIntro) {
                LocationPermissionIntroView {
                    showingLocationIntro = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
