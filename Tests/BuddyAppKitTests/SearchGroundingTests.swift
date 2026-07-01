//
//  SearchGroundingTests.swift
//  BuddyAppKitTests
//
//  Mirrors the relevant grounding tests from both apps' SearchInterpreter suites, to
//  protect the pure NL→filter grounding behavior now that it lives in BuddyAppKit.
//

import BuddyAppKit
import Testing

@Suite("Search grounding")
struct SearchGroundingTests {
    // MARK: - tokens

    @Test
    func `tokens are lowercased alphanumeric words, split on punctuation`() {
        #expect(SearchGrounding.tokens("Binary Search, Pads!") == ["binary", "search", "pads"])
        // Whole-word: "lin" is its own token, not found inside "linked".
        #expect(SearchGrounding.tokens("linked list") == ["linked", "list"])
        #expect(SearchGrounding.tokens("") == [])
    }

    // MARK: - optionList

    @Test
    func `option list caps length`() {
        let many = (1 ... 100).map { "lang\($0)" }
        #expect(SearchGrounding.optionList(many, limit: 3) == "lang1, lang2, lang3")
    }

    // MARK: - groundDateRange

    @Test
    func `grounds date range only when the query mentions time`() {
        #expect(SearchGrounding.groundDateRange("last 7 days", query: "python pads from last week")
            == "last 7 days")
        #expect(SearchGrounding.groundDateRange("last 7 days", query: "python pads") == nil)
        #expect(SearchGrounding.groundDateRange(nil, query: "from last week") == nil)
    }

    // MARK: - groundValue (whole-token vetting primitive)

    @Test
    func `grounds a value only when the query shares a whole word token`() {
        // A named topic word is shared → accepted.
        #expect(SearchGrounding.groundValue(against: ["javascript"], query: "javascript pads"))
        // The model's first-option guess isn't named → rejected.
        #expect(!SearchGrounding.groundValue(against: ["python", "python3"], query: "pads by rob"))
        // Empty candidate set never grounds.
        #expect(!SearchGrounding.groundValue(against: [], query: "anything"))
    }

    @Test
    func `min word length drops short tokens so single-letter initials cannot match`() {
        // A one-letter candidate is dropped at minWordLength 2, so it can't false-match.
        #expect(!SearchGrounding.groundValue(against: ["r"], query: "r pads", minWordLength: 2))
        // A real two-letter name still matches as a whole token.
        #expect(SearchGrounding.groundValue(against: ["jo", "li"], query: "pads by jo", minWordLength: 2))
        // ...but only as a whole token, not inside a longer word.
        #expect(!SearchGrounding.groundValue(against: ["li"], query: "linked list", minWordLength: 2))
    }

    // MARK: - groundText

    @Test
    func `grounds text to genuine keywords, dropping the supplied stop set`() {
        // A query the model echoes wholesale collapses to empty once its owner words are dropped.
        let ownerDrop = SearchGrounding.filterStopWords
            .union(SearchGrounding.tokens("Rob Di Marco"))
        #expect(SearchGrounding.groundText(raw: "pads by rob di marco", drop: ownerDrop).isEmpty)

        // A facet/language value word is dropped (the structured filter does the work).
        let langDrop = SearchGrounding.filterStopWords.union(["javascript"])
        #expect(SearchGrounding.groundText(raw: "javascript pads", drop: langDrop).isEmpty)

        // A real topic survives.
        #expect(SearchGrounding.groundText(raw: "binary search pads", drop: SearchGrounding.filterStopWords)
            == "binary search")
    }

    @Test
    func `filter stop words cover both apps' list vocabulary`() {
        // PadBuddy nouns.
        #expect(SearchGrounding.filterStopWords.contains("pads"))
        #expect(SearchGrounding.filterStopWords.contains("questions"))
        // RankBuddy nouns.
        #expect(SearchGrounding.filterStopWords.contains("tests"))
        #expect(SearchGrounding.filterStopWords.contains("candidates"))
        #expect(SearchGrounding.filterStopWords.contains("team"))
    }
}
