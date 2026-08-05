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
    public nonisolated enum BiometricUnavailabilityReason: Sendable, Equatable {
        case notEnrolled
        case lockout
        case unavailable
    }

    public nonisolated enum RevealAuthenticationPlan: Sendable, Equatable {
        case notRequired
        case biometrics
        case ownerAuthentication(BiometricUnavailabilityReason)
        case unavailable(BiometricUnavailabilityReason)
    }

    /// Once protection is enabled, a reveal always requires authentication; losing
    /// biometric availability must not silently disable the gate.
    public nonisolated static func shouldPrompt(
        settingEnabled: Bool,
        biometricsAvailable _: Bool
    ) -> Bool {
        settingEnabled
    }

    public nonisolated static func revealAuthenticationPlan(
        settingEnabled: Bool,
        biometricsAvailable: Bool,
        ownerAuthenticationAvailable: Bool,
        biometricFailure: BiometricUnavailabilityReason
    ) -> RevealAuthenticationPlan {
        guard settingEnabled else { return .notRequired }
        if biometricsAvailable { return .biometrics }
        if ownerAuthenticationAvailable { return .ownerAuthentication(biometricFailure) }
        return .unavailable(biometricFailure)
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

    /// Authenticate before revealing a secret. Returns `true` immediately only when the
    /// opt-in is off. If biometrics are unavailable, device-owner authentication is used
    /// as a fallback; if neither policy can run, the gate fails closed.
    ///
    /// - Parameters:
    ///   - settingEnabled: the app's stored opt-in (read from its own `@AppStorage` key).
    ///   - reason: the localized reason shown in the system prompt.
    @MainActor
    public static func authenticateForReveal(settingEnabled: Bool, reason: String) async -> Bool {
        #if os(tvOS)
            !settingEnabled
        #else
        guard settingEnabled else { return true }

        let context = LAContext()
        var biometricError: NSError?
        let biometricsAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometricError
        )
        let biometricFailure = biometricUnavailabilityReason(for: biometricError)
        let ownerAuthenticationAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        let plan = revealAuthenticationPlan(
            settingEnabled: true,
            biometricsAvailable: biometricsAvailable,
            ownerAuthenticationAvailable: ownerAuthenticationAvailable,
            biometricFailure: biometricFailure
        )

        let policy: LAPolicy
        switch plan {
        case .notRequired:
            return true
        case .biometrics:
            policy = .deviceOwnerAuthenticationWithBiometrics
        case .ownerAuthentication:
            policy = .deviceOwnerAuthentication
        case .unavailable:
            return false
        }

        return await (try? context.evaluatePolicy(policy, localizedReason: reason)) ?? false
        #endif
    }

    #if !os(tvOS)
        private nonisolated static func biometricUnavailabilityReason(
            for error: NSError?
        ) -> BiometricUnavailabilityReason {
            guard let error, error.domain == LAError.errorDomain else { return .unavailable }

            switch LAError.Code(rawValue: error.code) {
            case .biometryNotEnrolled:
                return .notEnrolled
            case .biometryLockout:
                return .lockout
            default:
                return .unavailable
            }
        }
    #endif

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
