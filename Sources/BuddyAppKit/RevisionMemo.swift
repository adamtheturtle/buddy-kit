//
//  RevisionMemo.swift
//  BuddyAppKit
//
//  A reference-type "recompute only when the signature changes" cache, lifted from
//  the coderpad list views. SwiftUI's `body` is re-evaluated on every selection
//  change, and an expensive derivation (filter + sort over a whole org, or rebuilding
//  chip-option lists) must not re-run each pass. A class — not `@State` — so `body`
//  can refresh it without mutating SwiftUI state mid-evaluation, keyed to a cheap
//  `Equatable` signature rather than "once per render".
//

import Foundation

/// Caches a derived `Value` and the `Signature` it was computed for, recomputing
/// only when the signature changes. Build a cheap signature from just the inputs the
/// derivation actually depends on (a revision counter, a filter-signature string, a
/// sort key) so unrelated `body` passes reuse the cached value.
public final class RevisionMemo<Value, Signature: Equatable> {
    private var signature: Signature?
    private var storage: Value

    // Workaround: Xcode 26.5's optimizer crashes on this generic class's
    // synthesized deinit; opt this type's deinit out of optimization.
    @_optimize(none)
    deinit {}

    /// Seeds the cache with the value to return before the first `value(for:compute:)`
    /// call (typically an empty collection).
    public init(_ initial: Value) {
        storage = initial
    }

    /// The currently cached value, without considering any signature.
    public var current: Value { storage }

    /// Returns the cached value when `signature` is unchanged from the last call,
    /// otherwise runs `compute`, stores its result under the new signature, and
    /// returns it.
    @discardableResult
    public func value(for signature: Signature, compute: () -> Value) -> Value {
        if self.signature != signature {
            self.signature = signature
            storage = compute()
        }
        return storage
    }
}
