//
//  SpotlightKeywordGeneratorTests.swift
//  BuddyAppKitTests
//
//  The pure reply parse for the on-device keyword generator (the model round-trip
//  itself is gated to macOS 26+ with an available model, so it isn't exercised here).
//

import BuddyAppKit
import Testing

@Suite("Spotlight keyword generator parse")
struct SpotlightKeywordGeneratorTests {
    @Test
    func `parses a comma-separated reply, lowercased and trimmed`() {
        #expect(SpotlightKeywordGenerator.parse("Binary Search, Recursion, Trees")
            == ["binary search", "recursion", "trees"])
    }

    @Test
    func `splits on newlines as well as commas and drops empties`() {
        #expect(SpotlightKeywordGenerator.parse("graphs,\n dfs \n, , bfs")
            == ["graphs", "dfs", "bfs"])
    }

    @Test
    func `caps at six keywords`() {
        let reply = "a, b, c, d, e, f, g, h"
        #expect(SpotlightKeywordGenerator.parse(reply) == ["a", "b", "c", "d", "e", "f"])
    }

    @Test
    func `an empty or whitespace reply yields no keywords`() {
        #expect(SpotlightKeywordGenerator.parse("").isEmpty)
        #expect(SpotlightKeywordGenerator.parse("  ,  \n ,").isEmpty)
    }

    @Test
    func `canonically equivalent keywords are returned once`() {
        let decomposedCafe = "cafe\u{301}"
        #expect(SpotlightKeywordGenerator.parse("Café, \(decomposedCafe), Trees")
            == ["café", "trees"])
    }

    @Test
    func `Unicode format controls are removed before indexing`() {
        let reply = "bi\u{202E}nary search, dy\u{200B}namic programming, \u{2066}\u{2069}"

        #expect(SpotlightKeywordGenerator.parse(reply) == ["binary search", "dynamic programming"])
    }
}
