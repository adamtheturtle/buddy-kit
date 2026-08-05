//
//  RelativeDateLabel.swift
//  BuddyAppKit
//

import Foundation

/// Caches a date's relative ("2 hours ago") and absolute tooltip strings so list
/// rows don't pay `Date.formatted(.relative:)`'s cost on every render.
///
/// `Date.formatted(.relative(presentation:))` re-creates its formatting machinery on
/// every call, and a `List` re-evaluates every visible row's body on each selection
/// pass — so on a large list this dominated the per-click cost (measured ~46% of the
/// stall on a 2500-pad list). The label is a pure function of the date and the current
/// time, so it's keyed by the date within a coarse time bucket: repeated reads within a
/// bucket hit the cache, and when the bucket rolls over the cache clears so relative
/// strings stay fresh. The strings are produced by the same `formatted` calls the rows
/// used inline, so the displayed wording is unchanged. Main-actor only, matching the
/// list rows that read it.
@MainActor
public enum RelativeDateLabel {
    public struct Labels {
        public let relative: String
        public let tooltip: String
    }

    private static var cache: [Date: Labels] = [:]
    private static var insertionOrder: [Date] = []
    private static var nextEvictionIndex = 0
    private static var bucket = 0
    /// Large enough to retain a full multi-thousand-row list while putting a
    /// strict ceiling on adversarial or long-running high-cardinality callers.
    static let cacheLimit = 4096
    /// Relative wording is coarse (minutes/hours/days), so a 30-second refresh window is
    /// imperceptible while keeping the cache hot across a selection's several renders.
    private static let bucketSeconds = 30.0

    public static func labels(for date: Date) -> Labels {
        labels(for: date, now: Date())
    }

    static func labels(for date: Date, now: Date) -> Labels {
        let currentBucket = Int(now.timeIntervalSinceReferenceDate / bucketSeconds)
        if currentBucket != bucket {
            cache.removeAll(keepingCapacity: true)
            insertionOrder.removeAll(keepingCapacity: true)
            nextEvictionIndex = 0
            bucket = currentBucket
        }
        if let hit = cache[date] {
            return hit
        }

        let labels = Labels(
            relative: date.formatted(.relative(presentation: .named)),
            tooltip: date.formatted(date: .long, time: .shortened)
        )
        if cache.count == cacheLimit {
            let evictedDate = insertionOrder[nextEvictionIndex]
            cache.removeValue(forKey: evictedDate)
            insertionOrder[nextEvictionIndex] = date
            nextEvictionIndex = (nextEvictionIndex + 1) % cacheLimit
        } else {
            insertionOrder.append(date)
        }
        cache[date] = labels
        return labels
    }

    static var cachedLabelCount: Int {
        cache.count
    }

    static func containsCachedLabels(for date: Date) -> Bool {
        cache[date] != nil
    }
}
