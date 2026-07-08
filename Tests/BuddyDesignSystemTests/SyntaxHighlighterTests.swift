//
//  SyntaxHighlighterTests.swift
//  BuddyDesignSystemTests
//

import BuddyDesignSystem
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
}
