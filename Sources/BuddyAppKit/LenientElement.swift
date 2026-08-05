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
    /// Distinguishes a successfully decoded value from an explicit JSON null and
    /// from a present value whose shape no longer matches `Wrapped`.
    public enum DecodingState: Sendable, Equatable {
        case value
        case null
        case malformed
    }

    public let value: Wrapped?
    public let decodingState: DecodingState

    public var isMalformed: Bool {
        decodingState == .malformed
    }

    public init(from decoder: any Decoder) {
        do {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                // Decode through `Wrapped` even for null so an optional Wrapped
                // preserves the outer "element was present" optional layer.
                value = try? container.decode(Wrapped.self)
                decodingState = .null
            } else {
                do {
                    value = try container.decode(Wrapped.self)
                    decodingState = .value
                } catch {
                    value = nil
                    decodingState = .malformed
                }
            }
        } catch {
            value = nil
            decodingState = .malformed
        }
    }
}
