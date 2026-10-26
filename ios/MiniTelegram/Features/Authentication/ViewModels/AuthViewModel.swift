import Foundation
import SwiftUI
import Combine

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public var username: String = ""
    @Published public var displayName: String = ""
    @Published public var phoneNumber: String = ""
    @Published public var password: String = ""
    @Published public var avatarBase64: String? = nil

    @Published public var inviteCode: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var validatedInvite: ValidateInviteResponse?
    @Published public var keyGenerationProgress: String?

    public init() {}

    // Normal Registration (No invite code required)
    public func registerNormal(appState: AppState) async -> Bool {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else {
            errorMessage = "Please enter your name"
            return false
        }
        guard cleanUsername.count >= 3 else {
            errorMessage = "Username must be at least 3 characters"
            return false
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
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
            let payload = RegisterRequest(
                username: cleanUsername,
                display_name: cleanName,
                password: password,
                phone_number: cleanPhone.isEmpty ? nil : cleanPhone,
                avatar_url: avatarBase64,
                device_name: deviceName,
                identity_key_pub: keys.identityAgreementPublicKeyBase64,
                signed_prekey_pub: keys.signedPrekeyPublicKeyBase64,
                signed_prekey_sig: keys.signedPrekeySignatureBase64,
                signed_prekey_id: keys.signedPrekeyId,
                one_time_prekeys: keys.oneTimePrekeys.map { OneTimePrekeyPayload(key_id: $0.keyId, public_key: $0.publicKeyBase64) }
            )

            // 3. Submit to Backend
            let authResponse: AuthResponse = try await APIClient.shared.request(
                endpoint: "/auth/register",
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
            let user = UserProfile(from: authResponse.user)
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

    public func register(appState: AppState) async -> Bool {
        return await registerNormal(appState: appState)
    }

    // Login with Phone Number OR Username
    public func loginWithIdentifier(identifier: String, pass: String, appState: AppState) async -> Bool {
        let cleanId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, !pass.isEmpty else {
            errorMessage = "Please enter your username/phone and password"
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            let payload = LoginRequest(
                username: cleanId,
                password: pass,
                device_name: UIDevice.current.name
            )

            let authResponse: AuthResponse = try await APIClient.shared.request(
                endpoint: "/auth/login",
                method: "POST",
                body: payload,
                requiresAuth: false
            )

            try KeychainManager.shared.saveString(key: "jwt_access_token", value: authResponse.tokens.access_token)
            try KeychainManager.shared.saveString(key: "jwt_refresh_token", value: authResponse.tokens.refresh_token)

            let user = UserProfile(from: authResponse.user)
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

    public func login(appState: AppState) async -> Bool {
        return await loginWithIdentifier(identifier: username, pass: password, appState: appState)
    }

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
}
