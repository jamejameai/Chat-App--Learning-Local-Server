import SwiftUI

@main
struct MiniTelegramApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appContainer = AppContainer.shared
    @StateObject private var localization = LocalizationManager.shared

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
        }
    }
}
