//
//  BuddyAppKitTests.swift
//  BuddyAppKitTests
//
//  Smoke tests for the extracted zero-coupling utilities (#511): just enough to
//  prove the package compiles and the pure helpers behave, since the app's own
//  suites carry the full coverage once these are wired back in.
//

import BuddyAppKit
import Foundation
import Testing

@Suite("BuddyAppKit utilities")
struct BuddyAppKitTests {
    @Test
    func `primaryID prefers a newly added id, then any remaining, else nil`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a"], current: ["a", "b"]) == "b")
        #expect(MultiSelectLogic.primaryID(previous: ["a", "b"], current: ["a"]) == "a")
        #expect(MultiSelectLogic.primaryID(previous: Set<String>(), current: []) == nil)
    }

    @Test
    func `staticURL builds a URL from a valid literal`() {
        #expect(URL.staticURL("https://example.com").absoluteString == "https://example.com")
        // `URL(string:)` is lenient (it percent-encodes most input), so the file-URL
        // fallback is a defensive last resort; what matters is staticURL never traps.
        #expect(!URL.staticURL("https://example.com/a b").absoluteString.isEmpty)
    }

    @Test
    func `LenientElement distinguishes decoded null and malformed values`() throws {
        let good = try JSONDecoder().decode(LenientElement<Int>.self, from: Data("7".utf8))
        #expect(good.value == 7)
        #expect(good.decodingState == .value)
        #expect(!good.isMalformed)

        let null = try JSONDecoder().decode(LenientElement<Int>.self, from: Data("null".utf8))
        #expect(null.value == nil)
        #expect(null.decodingState == .null)
        #expect(!null.isMalformed)

        let optionalNull = try JSONDecoder().decode(LenientElement<Int?>.self, from: Data("null".utf8))
        let preservesPresentElement: Bool
        switch optionalNull.value {
        case .some(.none): preservesPresentElement = true
        default: preservesPresentElement = false
        }
        #expect(preservesPresentElement)
        #expect(optionalNull.decodingState == .null)

        let bad = try JSONDecoder().decode(LenientElement<Int>.self, from: Data("\"nope\"".utf8))
        #expect(bad.value == nil)
        #expect(bad.decodingState == .malformed)
        #expect(bad.isMalformed)
    }
}

@Suite("Multi-selection primary row order")
struct MultiSelectOrderTests {
    private let order = ["a", "b", "c", "d", "e"]

    /// A shift-click range or Select All adds many ids at once, and `Set.first` is
    /// hash order seeded per process — so the detail pane showed an arbitrary row of
    /// the range, differing between runs for the same list (#4729).
    @Test func `a range selection takes the first added row in display order`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a"], current: ["a", "b", "c", "d"],
                                           order: order) == "b")
    }

    @Test func `select all takes the first row in display order`() {
        #expect(MultiSelectLogic.primaryID(previous: [], current: Set(order), order: order) == "a")
    }

    @Test func `a single added row still wins over the rest of the selection`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a", "b"], current: ["a", "b", "e"],
                                           order: order) == "e")
    }

    @Test func `a deselection falls back to the first remaining row in display order`() {
        #expect(MultiSelectLogic.primaryID(previous: ["b", "c", "d"], current: ["c", "d"],
                                           order: order) == "c")
    }

    @Test func `an empty selection has no primary`() {
        #expect(MultiSelectLogic.primaryID(previous: ["a"], current: [], order: order) == nil)
    }

    /// Ids the caller's list does not mention still resolve, so a stale order cannot
    /// blank the detail pane.
    @Test func `ids outside the display order still resolve`() {
        #expect(MultiSelectLogic.primaryID(previous: [], current: ["zz"], order: order) == "zz")
    }
}
