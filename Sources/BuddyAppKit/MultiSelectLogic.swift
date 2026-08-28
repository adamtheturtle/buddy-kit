//
//  MultiSelectLogic.swift
//  BuddyAppKit
//

import Foundation

/// Pure helpers for bridging a `List`'s multi-selection (`Set`) to the single
/// "primary" row that drives the detail pane. Kept free of SwiftUI so the rules
/// stay unit-testable in isolation.
public enum MultiSelectLogic {
    /// The row whose detail to show after the selection set changes: prefer a
    /// newly added id (the row the user just clicked or ⌘-clicked), falling back to
    /// any id still in the set, and `nil` when nothing is selected. This keeps the
    /// detail pane following the last-touched row while several rows stay selected
    /// for a bulk action.
    ///
    /// `order` is the rows as displayed. A single ⌘-click adds one id, so the choice
    /// is unambiguous, but a shift-click range or Select All adds many at once — and
    /// `Set.first` is hash order, which is seeded per process. Without the displayed
    /// order the detail pane showed an arbitrary row of the range, differing between
    /// runs for the same list (#4729). Ids missing from `order` fall back to the
    /// set's own iteration, so a caller that cannot supply the list still works.
    public static func primaryID<ID: Hashable>(
        previous: Set<ID>, current: Set<ID>, order: [ID]
    ) -> ID? {
        let added = current.subtracting(previous)
        let candidates = added.isEmpty ? current : added
        return order.first(where: candidates.contains) ?? candidates.first
    }

    /// The order-free form, kept for callers with no displayed list to hand over.
    ///
    /// Deterministic only when at most one id was added; see the overload above.
    public static func primaryID<ID: Hashable>(previous: Set<ID>, current: Set<ID>) -> ID? {
        primaryID(previous: previous, current: current, order: [])
    }
}
