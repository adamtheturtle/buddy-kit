//
//  CloudSyncStoreTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

struct CloudSyncStoreTests {
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
