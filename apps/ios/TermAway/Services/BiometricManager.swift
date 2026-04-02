import Foundation
import LocalAuthentication

@MainActor
class BiometricManager: ObservableObject {
    @Published var isLocked = false

    var biometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "biometricLockEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "biometricLockEnabled")
            objectWillChange.send()
        }
    }

    var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var biometricTypeName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Biometrics"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometrics"
        }
    }

    func authenticate() {
        guard isLocked else { return }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics unavailable — unlock anyway so user isn't stuck
            isLocked = false
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock TermAway"
        ) { success, _ in
            Task { @MainActor in
                if success {
                    self.isLocked = false
                }
            }
        }
    }

    func lockApp() {
        guard biometricEnabled else { return }
        isLocked = true
    }
}
