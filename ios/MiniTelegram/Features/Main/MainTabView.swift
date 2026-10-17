import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared

    public init() {}

    public var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                ConversationListView()
            }
            .tabItem {
                Label(L("tab_chats"), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppTab.chats)

            NavigationStack {
                CallsListView()
            }
            .tabItem {
                Label(L("tab_calls"), systemImage: "phone.fill")
            }
            .tag(AppTab.calls)

            NavigationStack {
                GroupsListView()
            }
            .tabItem {
                Label(L("tab_community"), systemImage: "person.2.fill")
            }
            .tag(AppTab.community)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(L("tab_settings"), systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(AppColors.accent)
    }
}

// Subview Placeholders with full Design System & Empty States
public struct ChatsPlaceholderView: View {
    public var body: some View {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: L("chats_empty_title"),
            description: L("chats_empty_description")
        )
        .navigationTitle(L("chats_title"))
        .navigationBarTitleDisplayMode(.large)
    }
}

public struct CallsPlaceholderView: View {
    public var body: some View {
        EmptyStateView(
            icon: "phone.badge.plus",
            title: L("calls_empty_title"),
            description: L("calls_empty_description")
        )
        .navigationTitle(L("calls_title"))
        .navigationBarTitleDisplayMode(.large)
    }
}

public struct GroupsPlaceholderView: View {
    public var body: some View {
        EmptyStateView(
            icon: "person.3",
            title: L("groups_title"),
            description: L("chats_empty_description")
        )
        .navigationTitle(L("groups_title"))
        .navigationBarTitleDisplayMode(.large)
    }
}

public struct SettingsPlaceholderView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared

    public var body: some View {
        List {
            Section(header: Text(L("settings_section_preferences"))) {
                HStack {
                    Text(L("settings_language"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { localization.currentLanguage },
                        set: { localization.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section(header: Text(L("settings_section_security"))) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(AppColors.accent)
                    Text(L("chat_e2ee_badge"))
                    Spacer()
                    Text("Verified")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.statusOnline)
                }
            }

            Section {
                Button(role: .destructive, action: {
                    appState.logout()
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(L("settings_logout"))
                    }
                }
            }
        }
        .navigationTitle(L("settings_title"))
        .navigationBarTitleDisplayMode(.large)
    }
}
