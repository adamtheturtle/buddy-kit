//
//  BiometricGate.swift
//  BuddyAppKit
//
//  A LocalAuthentication "reveal a secret / gate a toggle" helper shared by the
//  interview apps (#642). Two apps had the same inline `LAContext` dance in their
//  account editor and settings screens; this promotes it to one enum.
//
//  The `@AppStorage` opt-in key stays app-side (each app names its own); this helper
//  only takes a decision (`settingEnabled`) and a caller-supplied reason string, so it
//  carries no app-specific copy or defaults.
//

#if !os(tvOS)
    import LocalAuthentication
#endif

/// Biometric / device-owner authentication gate for revealing a stored secret or
/// guarding a destructive toggle.
public enum BiometricGate {
    /// Whether a reveal should be challenged at all: only when the user enabled the
    /// opt-in *and* the device actually has biometrics enrolled. Pure, so it's
    /// unit-testable.
    public nonisolated static func shouldPrompt(settingEnabled: Bool, biometricsAvailable: Bool) -> Bool {
        settingEnabled && biometricsAvailable
    }

    /// Whether this device can evaluate biometrics (Touch ID / Face ID) right now.
    public static var isBiometricsAvailable: Bool {
        #if os(tvOS)
            false
        #else
            LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        #endif
    }

    /// Whether the device can evaluate device-owner authentication (Touch ID / Face ID
    /// *or* the account password / passcode) right now.
    public static var canEvaluateOwnerAuth: Bool {
        #if os(tvOS)
            false
        #else
            LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        #endif
    }

    /// Authenticate before revealing a secret. Returns `true` immediately when no prompt
    /// is needed (the opt-in is off, or the device has no enrolled biometrics), otherwise
    /// the result of the biometric prompt. A failed or cancelled prompt returns `false`,
    /// so the caller leaves the secret hidden.
    ///
    /// - Parameters:
    ///   - settingEnabled: the app's stored opt-in (read from its own `@AppStorage` key).
    ///   - reason: the localized reason shown in the system prompt.
    @MainActor
    public static func authenticateForReveal(settingEnabled: Bool, reason: String) async -> Bool {
        #if os(tvOS)
            true
        #else
        guard shouldPrompt(settingEnabled: settingEnabled, biometricsAvailable: isBiometricsAvailable) else {
            return true
        }

        let context = LAContext()
        return await (try? context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason
        )) ?? false
        #endif
    }

    /// Authenticate before *disabling* a reveal gate (or performing any change that
    /// removes protection). Uses `.deviceOwnerAuthentication` so a password / passcode
    /// fallback is allowed. Returns `true` (permitting the change) immediately on devices
    /// that can't evaluate the policy, rather than trapping the user with the gate stuck
    /// on; otherwise returns the prompt's result, so a failed or cancelled prompt leaves
    /// the gate on.
    ///
    /// - Parameter reason: the localized reason shown in the system prompt.
    @MainActor
    public static func authenticateToDisableGate(reason: String) async -> Bool {
        #if os(tvOS)
            true
        #else
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }

        return await (try? context.evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: reason
        )) ?? false
        #endif
    }
}
