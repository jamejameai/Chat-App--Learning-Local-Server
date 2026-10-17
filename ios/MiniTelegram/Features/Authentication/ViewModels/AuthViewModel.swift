import Foundation
import SwiftUI
import Combine

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public var inviteCode: String = ""
    @Published public var username: String = ""
    @Published public var displayName: String = ""
    @Published public var password: String = ""

    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var validatedInvite: ValidateInviteResponse?
    @Published public var keyGenerationProgress: String?

    public init() {}

    public func validateInvitation(code: String) async -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L("auth_invitation_invalid")
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            struct ValidateBody: Codable {
                let code: String
            }
            let res: ValidateInviteResponse = try await APIClient.shared.request(
                endpoint: "/auth/invitation/validate",
                method: "POST",
                body: ValidateBody(code: trimmed),
                requiresAuth: false
            )

            validatedInvite = res
            isLoading = false
            return true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func register(appState: AppState) async -> Bool {
        guard let invite = validatedInvite, !inviteCode.isEmpty else {
            errorMessage = L("auth_invitation_invalid")
            return false
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a valid username"
            return false
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters long"
            return false
        }

        isLoading = true
        errorMessage = nil
        keyGenerationProgress = L("auth_generating_keys")

        do {
            // 1. Generate Hardware-backed X3DH Cryptographic Keys
            let keys = try CryptoIdentityService.shared.generateInitialDeviceKeys(oneTimePrekeyCount: 30)

            // 2. Prepare Payload
            let deviceName = UIDevice.current.name
            let payload = RegisterInviteRequest(
                invitation_code: inviteCode,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                display_name: displayName.isEmpty ? username : displayName,
                password: password,
                device_name: deviceName,
                identity_key_pub: keys.identityAgreementPublicKeyBase64,
                signed_prekey_pub: keys.signedPrekeyPublicKeyBase64,
                signed_prekey_sig: keys.signedPrekeySignatureBase64,
                signed_prekey_id: keys.signedPrekeyId,
                one_time_prekeys: keys.oneTimePrekeys.map { OneTimePrekeyPayload(key_id: $0.keyId, public_key: $0.publicKeyBase64) }
            )

            // 3. Submit to Backend
            let authResponse: AuthResponse = try await APIClient.shared.request(
                endpoint: "/auth/register-with-invite",
                method: "POST",
                body: payload,
                requiresAuth: false
            )

            // 4. Securely store secrets in Apple Keychain
            try KeychainManager.shared.saveString(key: "jwt_access_token", value: authResponse.tokens.access_token)
            try KeychainManager.shared.saveString(key: "jwt_refresh_token", value: authResponse.tokens.refresh_token)
            try KeychainManager.shared.save(key: "identity_agreement_priv", data: keys.identityAgreementPrivateKey.rawRepresentation)
            try KeychainManager.shared.save(key: "identity_signing_priv", data: keys.identitySigningPrivateKey.rawRepresentation)
            try KeychainManager.shared.save(key: "signed_prekey_priv", data: keys.signedPrekeyPrivateKey.rawRepresentation)
            try KeychainManager.shared.saveString(key: "identity_fingerprint", value: keys.identityFingerprint)

            // 5. Update Global Reactive App State
            let user = UserProfile(
                id: authResponse.user.id,
                username: authResponse.user.username,
                displayName: authResponse.user.display_name,
                role: authResponse.user.role,
                avatarUrl: authResponse.user.avatar_url
            )
            let device = DeviceProfile(
                id: authResponse.device.id,
                deviceName: authResponse.device.device_name ?? deviceName,
                identityKeyPub: keys.identityAgreementPublicKeyBase64
            )

            appState.setAuthenticated(user: user, device: device)
            isLoading = false
            keyGenerationProgress = nil
            return true
        } catch {
            isLoading = false
            keyGenerationProgress = nil
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func login(appState: AppState) async -> Bool {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = L("error_invalid_credentials")
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            struct LoginBody: Codable {
                let username: String
                let password: String
                let device_name: String
            }

            let authResponse: AuthResponse = try await APIClient.shared.request(
                endpoint: "/auth/login",
                method: "POST",
                body: LoginBody(username: username, password: password, device_name: UIDevice.current.name),
                requiresAuth: false
            )

            try KeychainManager.shared.saveString(key: "jwt_access_token", value: authResponse.tokens.access_token)
            try KeychainManager.shared.saveString(key: "jwt_refresh_token", value: authResponse.tokens.refresh_token)

            let user = UserProfile(
                id: authResponse.user.id,
                username: authResponse.user.username,
                displayName: authResponse.user.display_name,
                role: authResponse.user.role,
                avatarUrl: authResponse.user.avatar_url
            )
            let device = DeviceProfile(
                id: authResponse.device.id,
                deviceName: authResponse.device.device_name ?? "iPhone",
                identityKeyPub: authResponse.device.identity_key_pub ?? ""
            )

            appState.setAuthenticated(user: user, device: device)
            isLoading = false
            return true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return false
        }
    }
}
