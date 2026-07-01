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
    func `a reveal is challenged only when enabled and biometrics are available`() {
        #expect(BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: true))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: true))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: false))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: false))
    }
}
