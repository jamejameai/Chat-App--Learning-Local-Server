import SwiftUI
import UserNotifications

/// Settings › Notifications: Our Chat's own notification permission, and alerts for when the app is
/// closed, through the free Bark app (see BarkRelayManager).
public struct BackgroundNotificationsView: View {
    /// Shown once as a sheet after login, with a "Not now" button
    private let isPrompt: Bool

    @ObservedObject private var bark = BarkRelayManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var showDisconnectConfirm = false

    public init(isPrompt: Bool = false) {
        self.isPrompt = isPrompt
    }

    public var body: some View {
        List {
            if let error = bark.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(AppColors.statusError)
                        .font(AppTypography.footnote)
                }
            } else if let notice = bark.notice {
                Section {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundColor(AppColors.statusOnline)
                        .font(AppTypography.footnote)
                }
            }

            if bark.systemPermission != .authorized && bark.systemPermission != .provisional {
                permissionSection
            }

            closedAppSection

            if bark.settings?.configured == true {
                pingSoundSection

                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label(L("bark_disconnect"), systemImage: "bell.slash")
                    }
                }
            }
        }
        .navigationTitle(L("bark_title"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(bark.isBusy)
        .toolbar {
            if isPrompt {
                ToolbarItem(placement: .cancellationAction) {
                    Button(bark.settings?.configured == true ? L("bark_done") : L("bark_not_now")) {
                        dismiss()
                    }
                }
            }
            if bark.isBusy {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView()
                }
            }
        }
        .task {
            await bark.refreshSystemPermission()
            await bark.refresh()
        }
        .confirmationDialog(L("bark_disconnect"), isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button(L("bark_disconnect"), role: .destructive) {
                Task { await bark.disconnect() }
            }
            Button(L("action_cancel"), role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var permissionSection: some View {
        Section(header: Text(L("bark_permission_header"))) {
            Text(L("bark_permission_off"))
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
            Button {
                Task { await bark.requestSystemPermission() }
            } label: {
                Label(
                    bark.systemPermission == .denied ? L("bark_permission_open_settings") : L("bark_permission_allow"),
                    systemImage: "bell.badge"
                )
            }
        }
    }

    private var closedAppSection: some View {
        Section(
            header: Text(L("bark_closed_header")),
            footer: Text(L("bark_privacy"))
        ) {
            Text(L("bark_explain"))
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
                .padding(.vertical, AppSpacing.xxs)

            if let settings = bark.settings, settings.configured {
                Toggle(isOn: Binding(
                    get: { settings.enabled },
                    set: { enabled in Task { await bark.setEnabled(enabled) } }
                )) {
                    Label(L("bark_enabled"), systemImage: "bell.and.waves.left.and.right")
                }

                if let problem = bark.lastErrorText {
                    Text(problem)
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.statusError)
                    keyEntry(buttonTitle: L("bark_reconnect"))
                }

                soundPicker(
                    title: L("bark_message_sound"),
                    systemImage: "music.note",
                    selection: settings.messageSound,
                    sounds: settings.sounds
                ) { sound in
                    Task { await bark.setMessageSound(sound) }
                }

                soundPicker(
                    title: L("bark_call_sound"),
                    systemImage: "phone.arrow.down.left",
                    selection: settings.callSound,
                    sounds: settings.sounds
                ) { sound in
                    Task { await bark.setCallSound(sound) }
                }

                Button {
                    Task { await bark.sendTest() }
                } label: {
                    Label(L("bark_send_test"), systemImage: "paperplane")
                }
            } else {
                Link(destination: BarkRelayManager.appStoreURL) {
                    Label(L("bark_step_get"), systemImage: "arrow.down.app")
                }

                Text(L("bark_step_copy"))
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColors.textPrimary)

                Text(L("bark_step_paste"))
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColors.textPrimary)

                keyEntry(buttonTitle: L("bark_connect"))
            }
        }
    }

    private var pingSoundSection: some View {
        Section(header: Text(L("bark_ping_header"))) {
            Text(L("bark_ping_steps"))
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)

            if let pingURL = Bundle.main.url(forResource: "ping", withExtension: "caf") {
                ShareLink(item: pingURL) {
                    Label(L("bark_ping_save"), systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    // MARK: - Pieces

    /// Paste the address from Bark (PasteButton needs no "Allow Paste" prompt) and connect.
    private func keyEntry(buttonTitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                TextField(L("bark_key_placeholder"), text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.footnote, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.first ?? ""
                    Task { @MainActor in keyInput = pasted }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.iconOnly)
            }

            Button {
                Task {
                    if await bark.connect(key: keyInput) {
                        keyInput = ""
                    }
                }
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func soundPicker(
        title: String,
        systemImage: String,
        selection: String,
        sounds: [String],
        onChange: @escaping (String) -> Void
    ) -> some View {
        // Our ping (once imported into Bark) first, then Bark's built-in sounds
        var names = [BarkRelayManager.pingSoundName] + sounds.filter { $0 != BarkRelayManager.pingSoundName }
        if !names.contains(selection) { names.insert(selection, at: 0) }

        return Picker(selection: Binding(get: { selection }, set: onChange)) {
            ForEach(names, id: \.self) { name in
                Text(name == BarkRelayManager.pingSoundName ? L("bark_sound_ping") : name).tag(name)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .pickerStyle(.menu)
    }
}
