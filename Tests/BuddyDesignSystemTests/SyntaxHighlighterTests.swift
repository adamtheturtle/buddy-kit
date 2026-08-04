//
//  SyntaxHighlighterTests.swift
//  BuddyDesignSystemTests
//

@testable import BuddyDesignSystem
import Testing

@MainActor
struct SyntaxHighlighterTests {
    @Test("plain text is returned without highlighting")
    func plainTextReturnsSource() async {
        let highlighted = await SyntaxHighlighter.highlight("hello", language: "text", dark: false)

        #expect(String(highlighted.characters) == "hello")
    }

    @Test("known languages return the full source")
    func knownLanguageReturnsSource() async {
        let source = "let answer = 42"
        let highlighted = await SyntaxHighlighter.highlight(source, language: "swift", dark: false)

        #expect(String(highlighted.characters) == source)
    }

    @Test("changing appearance invalidates cached platform colours")
    func changingAppearanceInvalidatesCache() async {
        let engine = HighlightrEngine()

        _ = await engine.highlight("let light = true", language: "swift", dark: false)
        #expect(await engine.cachedResultCount == 1)

        _ = await engine.highlight("let dark = true", language: "swift", dark: true)
        #expect(await engine.cachedResultCount == 1)

        // Returning to light mode must not reuse colours resolved during the
        // previous light appearance; the new result is the cache's sole entry.
        _ = await engine.highlight("let light = true", language: "swift", dark: false)
        #expect(await engine.cachedResultCount == 1)
    }

    @Test("cache capacity evicts only the least-recently used result")
    func cacheCapacityUsesLRUEviction() async {
        let engine = HighlightrEngine()
        let firstSource = "let value0 = 0"
        let secondSource = "let value1 = 1"

        for index in 0 ..< HighlightrEngine.cacheLimit {
            _ = await engine.highlight("let value\(index) = \(index)", language: "swift", dark: false)
        }

        // Refresh the oldest entry, making the second insertion the LRU entry.
        _ = await engine.highlight(firstSource, language: "swift", dark: false)
        let overflowSource = "let overflow = true"
        _ = await engine.highlight(overflowSource, language: "swift", dark: false)

        let keptRecentlyUsed = await engine.containsCachedResult(firstSource, language: "swift", dark: false)
        let evictedLeastRecentlyUsed = await engine.containsCachedResult(secondSource, language: "swift", dark: false)
        let keptOverflow = await engine.containsCachedResult(overflowSource, language: "swift", dark: false)
        #expect(await engine.cachedResultCount == HighlightrEngine.cacheLimit)
        #expect(keptRecentlyUsed)
        #expect(!evictedLeastRecentlyUsed)
        #expect(keptOverflow)
    }
}
