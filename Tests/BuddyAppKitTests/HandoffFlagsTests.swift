//
//  HandoffFlagsTests.swift
//  BuddyAppKitTests
//
//  Covers `NSUserActivity.applyBuddyHandoffFlags` (#5): it sets the shared Handoff /
//  Spotlight eligibility flags and the `webpageURL`, and is callable from a `nonisolated`
//  context so a nonisolated `userActivity` update path can adopt it.
//

import Foundation
import Testing

@testable import BuddyAppKit

struct HandoffFlagsTests {
    // `nonisolated` proves the helper is callable without hopping to the main actor (#5);
    // it would not compile if `applyBuddyHandoffFlags` were MainActor-isolated.
    @Test nonisolated func `applyBuddyHandoffFlags sets eligibility from a nonisolated context`() {
        let activity = NSUserActivity(activityType: "com.example.item")
        let url = URL(string: "https://example.com/item/1")!
        activity.applyBuddyHandoffFlags(webpageURL: url)

        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch)
        #expect(activity.webpageURL == url)
    }

    @Test nonisolated func `applyBuddyHandoffFlags leaves webpageURL unset when none is given`() {
        let activity = NSUserActivity(activityType: "com.example.item")
        activity.applyBuddyHandoffFlags()

        #expect(activity.isEligibleForHandoff)
        #expect(activity.webpageURL == nil)
    }
}
