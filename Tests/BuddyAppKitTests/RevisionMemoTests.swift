//
//  RevisionMemoTests.swift
//  BuddyAppKitTests
//

import BuddyAppKit
import Testing

@Suite("Revision memo")
struct RevisionMemoTests {
    @Test
    func `it computes once for an unchanged signature and reuses the result`() {
        let memo = RevisionMemo<Int, String>(0)
        var computeCount = 0

        let first = memo.value(for: "sig-1") { computeCount += 1; return 42 }
        let second = memo.value(for: "sig-1") { computeCount += 1; return 99 }

        #expect(first == 42)
        // Same signature: the closure is not run again and the cached value stands.
        #expect(second == 42)
        #expect(computeCount == 1)
    }

    @Test
    func `it recomputes when the signature changes`() {
        let memo = RevisionMemo<Int, Int>(0)
        var computeCount = 0

        #expect(memo.value(for: 1) { computeCount += 1; return 10 } == 10)
        #expect(memo.value(for: 2) { computeCount += 1; return 20 } == 20)
        // Reverting to a previously-seen signature still recomputes (no history kept).
        #expect(memo.value(for: 1) { computeCount += 1; return 30 } == 30)
        #expect(computeCount == 3)
    }

    @Test
    func `current returns the seeded value before any computation`() {
        let memo = RevisionMemo<[String], Int>(["seed"])
        #expect(memo.current == ["seed"])

        memo.value(for: 1) { ["fresh"] }
        #expect(memo.current == ["fresh"])
    }
}
