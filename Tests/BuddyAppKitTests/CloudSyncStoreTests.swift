//
//  CloudSyncStoreTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Foundation
import Testing

struct CloudSyncStoreTests {
    @Test("cloud data reads reject values above the configured byte cap")
    func dataReadSizeLimit() {
        let limit = 4

        #expect(CloudSyncDataSizePolicy.isWithinLimit(
            Data(repeating: 0, count: limit), maximumBytes: limit
        ))
        #expect(!CloudSyncDataSizePolicy.isWithinLimit(
            Data(repeating: 0, count: limit + 1), maximumBytes: limit
        ))
        #expect(!CloudSyncDataSizePolicy.isWithinLimit(Data(), maximumBytes: -1))
    }

    @Test("stopped observation rejects queued and prior-generation changes")
    func stoppedObservationRejectsStaleWork() throws {
        var state = CloudSyncObservationState()
        let firstCandidate = state.start()
        let first = try #require(firstCandidate)
        let duplicateStart = state.start()

        #expect(duplicateStart == nil)
        #expect(state.isCurrent(first))

        state.stop()
        #expect(!state.isCurrent(first))

        let restartedCandidate = state.start()
        let restarted = try #require(restartedCandidate)
        #expect(restarted != first)
        #expect(!state.isCurrent(first))
        #expect(state.isCurrent(restarted))
    }

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
