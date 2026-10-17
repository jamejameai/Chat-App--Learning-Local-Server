import SwiftUI

@MainActor
public final class DeviceManagementViewModel: ObservableObject {
    @Published public var devices: [DeviceDTO] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?

    public func fetchDevices() async {
        isLoading = true
        errorMessage = nil
        do {
            let res: [DeviceDTO] = try await APIClient.shared.request(endpoint: "/devices")
            self.devices = res
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func revokeDevice(id: String) async {
        do {
            struct RevokeRes: Codable {
                let success: Bool
            }
            let _: RevokeRes = try await APIClient.shared.request(
                endpoint: "/devices/\(id)/revoke",
                method: "POST"
            )
            await fetchDevices()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

public struct DeviceManagementView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DeviceManagementViewModel()
    @State private var deviceToRevoke: DeviceDTO?
    @State private var showRevokeConfirm: Bool = false

    public init() {}

    public var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(AppColors.statusError)
                        .font(AppTypography.footnote)
                }
            }

            Section(header: Text(L("settings_active_devices", viewModel.devices.count))) {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.devices.isEmpty {
                    Text("No devices found")
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    ForEach(viewModel.devices, id: \.id) { dev in
                        let isCurrent = dev.id == appState.currentDevice?.id
                        let isRevoked = dev.is_revoked ?? false

                        HStack {
                            Image(systemName: "iphone")
                                .font(.system(size: 24))
                                .foregroundColor(isRevoked ? AppColors.textTertiary : AppColors.accent)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                HStack(spacing: AppSpacing.xs) {
                                    Text(dev.device_name ?? "iPhone")
                                        .font(AppTypography.body.weight(.semibold))
                                        .foregroundColor(isRevoked ? AppColors.textTertiary : AppColors.textPrimary)

                                    if isCurrent {
                                        Text("This Device")
                                            .font(AppTypography.caption.weight(.bold))
                                            .foregroundColor(AppColors.statusOnline)
                                            .padding(.horizontal, AppSpacing.xxs)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.12))
                                            .cornerRadius(AppCornerRadius.sm)
                                    }

                                    if isRevoked {
                                        Text("Revoked")
                                            .font(AppTypography.caption.weight(.bold))
                                            .foregroundColor(AppColors.statusError)
                                            .padding(.horizontal, AppSpacing.xxs)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.12))
                                            .cornerRadius(AppCornerRadius.sm)
                                    }
                                }

                                if let lastActive = dev.last_active_at {
                                    Text(lastActive)
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }

                            Spacer()

                            if !isCurrent && !isRevoked {
                                Button(role: .destructive) {
                                    deviceToRevoke = dev
                                    showRevokeConfirm = true
                                } label: {
                                    Text(L("action_delete"))
                                        .font(AppTypography.footnote)
                                        .foregroundColor(AppColors.statusError)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("settings_section_devices"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.fetchDevices()
        }
        .confirmationDialog(
            L("settings_revoke_device"),
            isPresented: $showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button(L("settings_revoke_device"), role: .destructive) {
                if let dev = deviceToRevoke {
                    Task {
                        await viewModel.revokeDevice(id: dev.id)
                    }
                }
            }
            Button(L("action_cancel"), role: .cancel) {}
        } message: {
            Text(L("settings_revoke_device_confirm"))
        }
    }
}
