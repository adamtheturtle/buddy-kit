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
}
