//
//  BiometricGateTests.swift
//  BuddyAppKitTests
//
//  Coverage for the biometric-reveal decision (#642). The actual Touch ID / Face ID
//  prompt can't run in tests, so this pins the pure gate (`shouldPrompt`). Mirrored from
//  RankBuddy's `BiometricAuthTests`.
//

import BuddyAppKit
import Testing

@Suite("Biometric gate")
struct BiometricGateTests {
    @Test
    func `enabled protection remains challenged when biometrics are unavailable`() {
        #expect(BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: true))
        #expect(BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: false))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: true))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: false))
    }

    @Test
    func `biometric policy transitions fall back or fail closed`() {
        #expect(BiometricGate.revealAuthenticationPlan(
            settingEnabled: false,
            biometricsAvailable: false,
            ownerAuthenticationAvailable: false,
            biometricFailure: .notEnrolled
        ) == .notRequired)
        #expect(BiometricGate.revealAuthenticationPlan(
            settingEnabled: true,
            biometricsAvailable: true,
            ownerAuthenticationAvailable: true,
            biometricFailure: .unavailable
        ) == .biometrics)
        #expect(BiometricGate.revealAuthenticationPlan(
            settingEnabled: true,
            biometricsAvailable: false,
            ownerAuthenticationAvailable: true,
            biometricFailure: .notEnrolled
        ) == .ownerAuthentication(.notEnrolled))
        #expect(BiometricGate.revealAuthenticationPlan(
            settingEnabled: true,
            biometricsAvailable: false,
            ownerAuthenticationAvailable: true,
            biometricFailure: .lockout
        ) == .ownerAuthentication(.lockout))
        #expect(BiometricGate.revealAuthenticationPlan(
            settingEnabled: true,
            biometricsAvailable: false,
            ownerAuthenticationAvailable: false,
            biometricFailure: .lockout
        ) == .unavailable(.lockout))
    }
}
