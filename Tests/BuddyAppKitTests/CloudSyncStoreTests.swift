//
//  CloudSyncStoreTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

struct CloudSyncStoreTests {
    @Test("iOS provisioned hosts can explicitly enable iCloud KVS")
    func explicitEntitlementConfiguration() {
        #expect(!CloudSyncEntitlementGate.allowsStore(
            runtimeDetected: nil, hostConfigured: false
        ))
        #expect(CloudSyncEntitlementGate.allowsStore(
            runtimeDetected: nil, hostConfigured: true
        ))
    }

    @Test("runtime entitlement detection remains authoritative")
    func runtimeEntitlementDetection() {
        #expect(!CloudSyncEntitlementGate.allowsStore(
            runtimeDetected: false, hostConfigured: true
        ))
        #expect(CloudSyncEntitlementGate.allowsStore(
            runtimeDetected: true, hostConfigured: false
        ))
    }

    @Test("iCloud activates once when availability appears after launch")
    func unavailableToAvailableTransition() {
        var state = CloudSyncActivationState()

        let initiallyUnavailable = state.consumeAvailability(false)
        let firstAvailability = state.consumeAvailability(true)
        let repeatedAvailability = state.consumeAvailability(true)
        let laterUnavailability = state.consumeAvailability(false)
        let secondAvailability = state.consumeAvailability(true)

        #expect(!initiallyUnavailable)
        #expect(firstAvailability)
        #expect(!repeatedAvailability)
        #expect(!laterUnavailability)
        #expect(!secondAvailability)
    }
}
