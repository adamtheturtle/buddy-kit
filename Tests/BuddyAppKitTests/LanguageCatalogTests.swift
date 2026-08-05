//
//  LanguageCatalogTests.swift
//  BuddyAppKitTests
//
//  Pins the reconciled language-code -> display-name table (#640) so both apps' codes
//  resolve to the same friendly names.
//

import BuddyAppKit
import Testing

@Suite("Language catalog")
struct LanguageCatalogTests {
    @Test
    func `maps canonical codes to display names`() {
        #expect("cpp".languageDisplayName == "C++")
        #expect("py".languageDisplayName == "Python")
        #expect("python".languageDisplayName == "Python")
        #expect("csharp".languageDisplayName == "C#")
        #expect("nodejs".languageDisplayName == "Node.js")
        #expect("objc".languageDisplayName == "Objective-C")
    }

    @Test
    func `lookup is case-insensitive`() {
        #expect("CPP".languageDisplayName == "C++")
        #expect("JavaScript".languageDisplayName == "JavaScript")
    }

    @Test
    func `aliases from both apps resolve`() {
        // RankBuddy-side aliases.
        #expect("js".languageDisplayName == "JavaScript")
        #expect("ts".languageDisplayName == "TypeScript")
        #expect("postgres".languageDisplayName == "PostgreSQL")
        // PadBuddy-side entries.
        #expect("fsharp".languageDisplayName == "F#")
        #expect("solidity".languageDisplayName == "Solidity")
    }

    @Test
    func `unknown codes are title-cased and empty stays empty`() {
        #expect("brainfuck".languageDisplayName == "Brainfuck")
        #expect("".languageDisplayName == "")
    }

    @Test
    func `unknown codes title-case expanding first graphemes once`() {
        #expect("ßlang".languageDisplayName == "Sslang")
        #expect("ﬃscript".languageDisplayName == "Ffiscript")
        #expect("ǳcode".languageDisplayName == "ǲcode")
    }

    @Test
    func `the backing table is exposed for direct lookup`() {
        #expect(LanguageCatalog.displayNames["c++"] == "C++")
    }
}
