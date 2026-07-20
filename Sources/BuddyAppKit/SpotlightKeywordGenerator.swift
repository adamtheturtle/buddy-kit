//
//  SpotlightKeywordGenerator.swift
//  BuddyAppKit
//
//  On-device keyword generation for Spotlight indexing (#644). Both apps run the same
//  ~30-line round-trip: check the model is available, send a "three to six short,
//  lowercase keywords" instructions prompt with the item's brief, then split / trim /
//  cap the reply into keywords. Extracted so the model round-trip lives once; each app
//  keeps only its own brief construction and its own re-index loop (PadBuddy's
//  IndexedEntity vs RankBuddy's raw CSSearchableItem).
//
//  CRITICAL: this uses the plain-text `respond(to:)` path, NOT `@Generable`. The
//  `Generable.promptRepresentation` accessor the macro emits is absent on some shipping
//  OS builds and aborts the process at dyld load, so `@Generable` must never appear in
//  buddy-kit. PadBuddy currently uses `@Generable` for this and moves to this path.
//

import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Generates a few topical Spotlight keywords for an item from its brief, using Apple's
/// on-device model over the plain-text response path. Degrades gracefully — returns `[]`
/// — whenever the model is unavailable, the brief is empty, or generation fails, so a
/// caller can always call it and simply attach nothing.
public enum SpotlightKeywordGenerator {
    /// The instructions that set the model's job and guardrails for every keyword set.
    /// The plain-text reply is a comma/newline-separated list, so the prompt asks for
    /// exactly that shape.
    private static let instructions = """
    You generate concise search keywords for coding interview items so they can be found \
    by topic. Return three to six short, lowercase keywords (data structures, algorithms, \
    skills, languages, or problem themes), separated by commas. No sentences, no \
    explanations, and no numbering.
    """

    /// Whether the on-device model can generate keywords right now, so a caller can skip
    /// an enrichment pass entirely otherwise.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, visionOS 26, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// A few topical keywords for `brief` (e.g. "binary search", "recursion"), or an
    /// empty array when the model is unavailable, the brief is empty, or generation
    /// produced nothing usable. On-device only; the brief never leaves the device.
    ///
    /// The caller assembles `brief` from the fields it already fetched (title, tags,
    /// languages, a capped body) and applies the returned keywords to its own index item.
    public static func keywords(from brief: String) async -> [String] {
        let trimmed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, visionOS 26, *) {
                guard SystemLanguageModel.default.availability == .available else { return [] }

                let session = LanguageModelSession(instructions: instructions)
                do {
                    // Plain-text `respond(to:)` (not `generating:`): the reply is a
                    // comma/newline list this parses, never a `@Generable` type.
                    let response = try await session.respond(to: trimmed)
                    return parse(response.content)
                } catch {
                    return []
                }
            }
        #endif
        return []
    }

    /// Splits the model's comma/newline-separated reply into trimmed, lowercased,
    /// non-empty keywords, capped at six. Pure and off-main-safe, so the parse is
    /// unit-testable without the model.
    public nonisolated static func parse(_ reply: String) -> [String] {
        let parsed = reply
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Array(parsed.prefix(6))
    }
}
