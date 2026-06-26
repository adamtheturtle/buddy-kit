//
//  CloudSyncMerge.swift
//  BuddyAppKit
//
//  Cross-device merge helpers for the per-account favourite / saved-search / history
//  blobs, lifted from the coderpad iCloud-sync foundation. Pure functions so the
//  merge semantics are unit-testable without iCloud; an app's `CloudSyncStore`
//  orchestration only does I/O around them.
//
//  The blobs are keyed locally by a per-device account `UUID` and in the cloud by a
//  stable, cross-device sync id `String` (an app supplies the mapping both ways).
//  All merges are additive and last-writer-wins by recency where timestamps apply;
//  deletions do NOT propagate, a safe-by-default choice while element-level merge is
//  out of scope (a removal on one device won't wipe the item on another).
//

import Foundation

public nonisolated enum CloudSyncMerge {
    /// Projects a local, per-`UUID` blob into its cloud form keyed by stable sync id,
    /// dropping accounts whose sync id is empty (drafts) or that `syncID` can't
    /// resolve. When two local accounts share a sync id the last one wins, which is
    /// harmless for a mirror.
    public static func toCloud<Value>(_ local: [UUID: Value], syncID: (UUID) -> String?) -> [String: Value] {
        var cloud: [String: Value] = [:]
        for (uuid, value) in local {
            guard let identity = syncID(uuid), !identity.isEmpty else { continue }

            cloud[identity] = value
        }
        return cloud
    }

    /// Merges a cloud blob (keyed by sync id) back into a local one (keyed by `UUID`),
    /// additively per account: each array is unioned with local order preserved and
    /// cloud-only elements appended, so neither device's items are lost. Deletions do
    /// NOT propagate. `uuidForSyncID` resolves a stable id back to a configured local
    /// account; cloud entries for accounts not present on this device are ignored.
    public static func mergeArrays<Element: Equatable>(
        cloud: [String: [Element]],
        into local: [UUID: [Element]],
        uuidForSyncID: (String) -> UUID?
    ) -> [UUID: [Element]] {
        var merged = local
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var list = merged[uuid] ?? []
            for element in cloudList where !list.contains(element) {
                list.append(element)
            }
            merged[uuid] = list
        }
        return merged
    }

    /// Like ``mergeArrays(cloud:into:uuidForSyncID:)`` but unions each account's array
    /// by a stable element `id` rather than by full-value equality, so the same logical
    /// item is never duplicated when a mutable field differs between devices — e.g. an
    /// item whose captured title was backfilled on one device but not the other, or one
    /// the user renamed. The local entry wins for ids present on both sides (it isn't
    /// overwritten); cloud-only items are appended, preserving local order.
    public static func mergeArrays<Element>(
        cloud: [String: [Element]],
        into local: [UUID: [Element]],
        uuidForSyncID: (String) -> UUID?,
        id: (Element) -> AnyHashable
    ) -> [UUID: [Element]] {
        var merged = local
        for (identity, cloudList) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var list = merged[uuid] ?? []
            var present = Set(list.map(id))
            for element in cloudList where present.insert(id(element)).inserted {
                list.append(element)
            }
            merged[uuid] = list
        }
        return merged
    }

    /// The nested counterpart of the id-keyed ``mergeArrays(cloud:into:uuidForSyncID:id:)``,
    /// for collections partitioned by an inner string key before the array — e.g. saved
    /// searches kept per account *and* per list kind. Unions each (account, kind) bucket
    /// by element `id` with the same semantics.
    public static func mergeNestedArrays<Element>(
        cloud: [String: [String: [Element]]],
        into local: [UUID: [String: [Element]]],
        uuidForSyncID: (String) -> UUID?,
        id: (Element) -> AnyHashable
    ) -> [UUID: [String: [Element]]] {
        var merged = local
        for (identity, cloudBuckets) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var buckets = merged[uuid] ?? [:]
            for (bucketKey, cloudList) in cloudBuckets {
                var list = buckets[bucketKey] ?? []
                var present = Set(list.map(id))
                for element in cloudList where present.insert(id(element)).inserted {
                    list.append(element)
                }
                buckets[bucketKey] = list
            }
            merged[uuid] = buckets
        }
        return merged
    }

    /// Merges a cloud "last activity" blob (sync id -> item id -> date) into the local
    /// per-`UUID` one, keeping the MOST RECENT timestamp per item so an action taken on
    /// any device wins everywhere. Unlike the array merges this is a last-writer-by-
    /// recency union: monotonic, so no recorded timestamp is ever lost, and an older
    /// cloud copy never resurrects a superseded value.
    public static func mergeTimestamps(
        cloud: [String: [String: Date]],
        into local: [UUID: [String: Date]],
        uuidForSyncID: (String) -> UUID?
    ) -> [UUID: [String: Date]] {
        var merged = local
        for (identity, cloudDates) in cloud {
            guard let uuid = uuidForSyncID(identity) else { continue }

            var dates = merged[uuid] ?? [:]
            for (itemID, date) in cloudDates where date > (dates[itemID] ?? .distantPast) {
                dates[itemID] = date
            }
            merged[uuid] = dates
        }
        return merged
    }
}
