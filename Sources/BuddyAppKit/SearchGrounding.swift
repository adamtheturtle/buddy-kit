//
//  SearchGrounding.swift
//  BuddyAppKit
//
//  The pure natural-language grounding core shared by both apps' `SearchInterpreter`
//  (PadBuddy #639, RankBuddy #91). An on-device model turns a plain request ("python
//  pads from last week") into candidate filter values; the small model over-fills
//  fields the request never named, so these pure checks keep a value only when the
//  query actually supports it — turning the model into a candidate generator that
//  testable code vets. This is only the grounding vocabulary and word-matching: the
//  model call, the prompt, and the app's own filter shapes all stay app-side. Nothing
//  here touches FoundationModels or `@Generable`, so it's fully unit-testable and safe
//  on every OS.
//

import Foundation

/// Pure, off-main-safe natural-language grounding helpers shared by both apps'
/// search interpreters. Every function is a candidate-vetting predicate over the
/// user's raw query; none reaches for the model or any app type.
public nonisolated enum SearchGrounding {
    /// Lowercased alphanumeric word tokens of `text`, for whole-word comparison against
    /// the query (so "lin" doesn't match inside "linked").
    public static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty })
    }

    /// A short, comma-separated list of options to steer the model, capped so a big
    /// org's value list can't dominate the prompt.
    public static func optionList(_ values: [String], limit: Int) -> String {
        values.prefix(limit).joined(separator: ", ")
    }

    /// Words that name a filter concept rather than a list-item title, so they must
    /// never survive into the free-text search. Covers the list nouns, connectors, and
    /// the state/type/recency vocabulary both apps' models otherwise leave in the text.
    /// The union of PadBuddy's and RankBuddy's stop-word sets: a superset word (e.g.
    /// "candidate", "team", "test") only ever helps strip a genuine filter concept, so
    /// sharing one list is safe for both.
    public static let filterStopWords: Set<String> = [
        // List nouns (pads, questions, tests, interviews, people, teams).
        "pad", "pads", "question", "questions", "interview", "interviews",
        "test", "tests", "candidate", "candidates", "user", "users", "team", "teams",
        // Connectors and pronouns.
        "by", "from", "the", "a", "an", "of", "in", "on", "for", "with", "and", "or",
        "my", "me", "mine", "show", "find", "all", "owned", "created", "made",
        "that", "are",
        // State / type vocabulary.
        "active", "ended", "pending", "started", "finished", "open", "closed",
        "live", "take", "home", "takehome", "draft", "published",
        // Recency vocabulary.
        "today", "yesterday", "last", "recent", "recently", "past", "this",
        "day", "days", "week", "weeks", "month", "months", "hour", "hours",
        "year", "years"
    ]

    /// The recency vocabulary that lets a resolved date window survive: only when the
    /// query actually mentions a time frame does the model's proposed range stick.
    public static let dateWords: Set<String> = [
        "today", "yesterday", "week", "weeks", "month", "months", "day", "days",
        "hour", "hours", "recent", "recently", "last", "past", "this",
        "24", "7", "30", "90", "year", "years"
    ]

    /// Keeps a resolved date window only when the query mentions a time frame, so the
    /// model can't attach a range the request never implied.
    public static func groundDateRange(_ range: String?, query: String) -> String? {
        guard let range else { return nil }

        return tokens(query).isDisjoint(with: dateWords) ? nil : range
    }

    /// Keeps a model-proposed value only when the query names it: the value must share a
    /// whole word token with the query. `minWordLength` drops sub-length tokens before
    /// comparing, so single-letter initials don't false-match while real short names
    /// ("Jo", "Li") or two-letter codes still do; pass `1` to compare every token.
    ///
    /// This is the primitive both apps' field grounders reduce to — a language code and
    /// its display name, an owner's name words, a team name, a facet option — so they
    /// can share one whole-token vetting rule instead of re-deriving it per field.
    public static func groundValue(against candidateWords: Set<String>,
                                   query: String,
                                   minWordLength: Int = 1) -> Bool {
        let accepted = minWordLength > 1
            ? candidateWords.filter { $0.count >= minWordLength }
            : candidateWords
        guard !accepted.isEmpty else { return false }

        return !tokens(query).isDisjoint(with: accepted)
    }

    /// Strips the model's free-text down to genuine title keywords: drops the stop-word
    /// `drop` set (typically ``filterStopWords`` unioned with the words of every matched
    /// filter value — a language's code and display name, an owner's name, a team, a
    /// facet option). So a query the model echoes wholesale ("pads by rob di marco")
    /// collapses to empty and the structured filters do the work, while a real topic
    /// ("binary search") survives.
    ///
    /// Generalized over PadBuddy's `groundText(_:languages:ownerName:team:)` and
    /// RankBuddy's `groundText(_:facetValueWords:)`: both build a drop set and run this
    /// same whitespace-split / alphanumeric-key / membership filter, so the shared core
    /// takes the finished set and each app assembles its own.
    public static func groundText(raw: String, drop: Set<String>) -> String {
        let kept = raw
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { word in
                let key = word.lowercased().filter { $0.isLetter || $0.isNumber }
                return !key.isEmpty && !drop.contains(key)
            }
        return kept.joined(separator: " ")
    }
}
