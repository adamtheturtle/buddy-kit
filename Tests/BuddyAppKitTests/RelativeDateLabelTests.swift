//
//  RelativeDateLabelTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Foundation
import Testing

@MainActor
struct RelativeDateLabelTests {
    @Test("high-cardinality input stays within the date-label cache limit")
    func highCardinalityInputIsBounded() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let firstDate = Date(timeIntervalSinceReferenceDate: 0)

        for offset in 0 ... RelativeDateLabel.cacheLimit {
            let date = Date(timeIntervalSinceReferenceDate: Double(offset))
            _ = RelativeDateLabel.labels(for: date, now: now)
        }

        let lastDate = Date(timeIntervalSinceReferenceDate: Double(RelativeDateLabel.cacheLimit))
        #expect(RelativeDateLabel.cachedLabelCount == RelativeDateLabel.cacheLimit)
        #expect(!RelativeDateLabel.containsCachedLabels(for: firstDate))
        #expect(RelativeDateLabel.containsCachedLabels(for: lastDate))
    }
}
