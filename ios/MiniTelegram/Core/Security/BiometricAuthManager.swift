import Foundation
import LocalAuthentication

public enum BiometricType {
    case none
    case touchID
    case faceID
}

@MainActor
public final class BiometricAuthManager {
    public static let shared = BiometricAuthManager()

    private let isBiometricEnabledKey = "is_biometric_lock_enabled"

    public var isBiometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isBiometricEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isBiometricEnabledKey) }
    }

    public var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                return .faceID
            case .touchID:
                return .touchID
            default:
                return .none
            }
        }
        return .none
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
