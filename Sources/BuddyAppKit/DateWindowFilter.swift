//
//  DateWindowFilter.swift
//  BuddyAppKit
//
//  View-free date filtering primitives lifted from the coderpad app's pad list
//  logic. A `NamedDateRange` resolves a human label ("last 7 days") to a lower
//  bound, a `DateWindow` pairs such a named window with an optional explicit custom
//  range, and `ListFilterCriteria` is the small seam each app implements over its
//  own model so the windowing here can be reused without importing the app target.
//

import Foundation

/// The lower bound a value's date must satisfy for a named date-range filter. `now`
/// is injectable so callers (and tests) stay deterministic rather than depending on
/// the wall clock.
public nonisolated enum NamedDateRange {
    /// The labels used both for the filter chips and as the keys understood here.
    public static let options = ["today", "last 24 hours", "last 7 days", "last 30 days", "last 90 days"]

    /// The earliest date a value may carry to satisfy `option`, or `nil` for an
    /// unrecognized option (treated as "no lower bound").
    ///
    /// Multi-day windows anchor to *calendar-day* boundaries rather than a rolling
    /// count of hours, so "last 7 days" means today plus the six prior whole days
    /// and stays stable as the clock advances through the day (matching Gmail /
    /// Linear). "Last 24 hours" is the deliberate exception — it names an hour
    /// window, so it rolls.
    public static func start(for option: String,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        switch option {
        case "today": return startOfToday
        case "last 24 hours": return calendar.date(byAdding: .hour, value: -24, to: now)
        case "last 7 days": return calendar.date(byAdding: .day, value: -6, to: startOfToday)
        case "last 30 days": return calendar.date(byAdding: .day, value: -29, to: startOfToday)
        case "last 90 days": return calendar.date(byAdding: .day, value: -89, to: startOfToday)
        default: return nil
        }
    }
}

/// One date-range constraint: a named window key (one of `NamedDateRange.options`)
/// and/or an explicit custom range. A custom range overrides the named window. An
/// all-nil window imposes no constraint. A list typically carries two of these — one
/// applied to an updated date, one to a created date — so they can be filtered
/// independently and at the same time.
public nonisolated struct DateWindow: Equatable, Hashable, Codable, Sendable {
    public var range: String?
    public var customStart: Date?
    public var customEnd: Date?

    public init(range: String? = nil, customStart: Date? = nil, customEnd: Date? = nil) {
        self.range = range
        self.customStart = customStart
        self.customEnd = customEnd
    }

    public var isActive: Bool {
        range != nil || customStart != nil || customEnd != nil
    }

    /// A stable change token covering the named range *and* the custom bounds, so a
    /// signature built from it changes when a custom range does. Two different
    /// custom ranges (both with `range == nil`) must not collapse to one token.
    public var signatureToken: String {
        [range,
         customStart.map { String($0.timeIntervalSince1970) },
         customEnd.map { String($0.timeIntervalSince1970) }]
            .map { $0 ?? "·" }.joined(separator: ",")
    }

    /// Whether `value` falls within this window. `now` resolves a named window to a
    /// lower bound; a custom range supplies explicit inclusive bounds. An inactive
    /// window contains everything.
    public func contains(_ value: Date, now: Date) -> Bool {
        let lower = customStart ?? range.flatMap { NamedDateRange.start(for: $0, now: now) }
        return (lower.map { value >= $0 } ?? true)
            && (customEnd.map { value <= $0 } ?? true)
    }
}

/// The small seam each app implements over its own model: given an item and a
/// reference `now`, decide whether it matches. Apps keep their concrete, model-aware
/// criteria struct (which fields, which semantics) while the windowing, text-match,
/// and memoization scaffolding here stay domain-neutral.
public protocol ListFilterCriteria {
    associatedtype Item
    nonisolated func matches(_ item: Item, now: Date) -> Bool
}

public extension Sequence {
    /// Filter by a `ListFilterCriteria` over this element type. Factored as a free
    /// helper so the single-list and merged-list call sites share one predicate and
    /// can never drift.
    nonisolated func filtered<Criteria: ListFilterCriteria>(
        by criteria: Criteria,
        now: Date = Date()
    ) -> [Element] where Criteria.Item == Element {
        filter { criteria.matches($0, now: now) }
    }
}
