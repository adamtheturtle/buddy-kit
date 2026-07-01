//
//  LenientElement.swift
//  BuddyAppKit
//

import Foundation

/// Wraps a decodable element so a per-element decode failure yields `nil` instead of
/// aborting the whole array — letting a loader drop an individual invalid element
/// while keeping the rest.
///
/// `nonisolated` because models decode off the main actor inside a REST client, while
/// `BuddyAppKit`'s default actor isolation is `MainActor`; without this, the synthesized
/// `Decodable` conformance would be `MainActor`-isolated and unusable from an off-main
/// `init(from:)`. The type is a value type whose only stored property is an immutable
/// `Wrapped?`, so it stays trivially `Sendable` whenever `Wrapped` is (the conditional
/// `Sendable` the compiler would synthesize is unaffected by the isolation change).
public nonisolated struct LenientElement<Wrapped: Decodable>: Decodable {
    public let value: Wrapped?

    public init(from decoder: any Decoder) {
        value = try? decoder.singleValueContainer().decode(Wrapped.self)
    }
}
