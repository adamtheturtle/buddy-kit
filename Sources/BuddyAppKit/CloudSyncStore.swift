//
//  CloudSyncStore.swift
//  BuddyAppKit
//
//  A thin, best-effort mirror of small per-account collections into iCloud's
//  key-value store, lifted from the coderpad iCloud-sync foundation. A no-op whenever
//  iCloud is unavailable, so call sites stay oblivious to iCloud and a build without
//  the ubiquity entitlement (e.g. an unprovisioned Developer ID build) is unaffected.
//
//  Design notes:
//  - The host app's local store (UserDefaults/Keychain) stays the source of truth.
//    This only pushes a copy up and pulls external changes down, so when iCloud is
//    unavailable every method is a no-op and behaviour is exactly as before.
//  - iCloud's key-value store needs the profile-gated `ubiquity-kvstore-identifier`
//    entitlement. On a build that can't carry it, `isAvailable` is false and none of
//    this runs.
//  - Credentials must NEVER pass through here; keep secrets in the Keychain (which
//    has its own opt-in iCloud Keychain sync) and mirror only non-secret state.
//

import Foundation
import Security

/// A thin, best-effort mirror of small per-account collections into iCloud's
/// key-value store. A no-op whenever iCloud is unavailable.
@MainActor
public final class CloudSyncStore {
    public static let shared = CloudSyncStore()

    /// Posted after an external iCloud change has arrived, with the changed cloud key
    /// in `userInfo["key"]`, so the owning store can re-pull and merge.
    public static let didChangeExternally = Notification.Name("CloudSyncStore.didChangeExternally")

    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var observerTask: Task<Void, Never>?
    private var identityObserverTask: Task<Void, Never>?
    private var activationState = CloudSyncActivationState()
    private var configuredUbiquityEntitlement = false

    private init() {}

    /// The shared iCloud KVS, accessed lazily and ONLY behind ``isAvailable`` — merely
    /// referencing `NSUbiquitousKeyValueStore.default` without the ubiquity entitlement
    /// logs "BUG IN CLIENT OF KVS: …", so it must never be touched on an unentitled build.
    private var store: NSUbiquitousKeyValueStore {
        .default
    }

    /// Whether the app actually carries the `ubiquity-kvstore-identifier` entitlement.
    /// Checked once via the code signature: being signed into iCloud is NOT enough
    /// (`ubiquityIdentityToken` is non-nil whenever iCloud is on, entitlement or not), so
    /// this is the gate that keeps KVS untouched on an unprovisioned build.
    private static let detectedUbiquityEntitlement: Bool? = {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil) else { return false }

            let key = "com.apple.developer.ubiquity-kvstore-identifier" as CFString
            return SecTaskCopyValueForEntitlement(task, key, nil) != nil
        #else
            // iOS/iPadOS has no public equivalent of the macOS SecTask check. The host
            // must explicitly confirm its provisioned capability before KVS is touched.
            return nil
        #endif
    }()

    private var hasUbiquityEntitlement: Bool {
        CloudSyncEntitlementGate.allowsStore(
            runtimeDetected: Self.detectedUbiquityEntitlement,
            hostConfigured: configuredUbiquityEntitlement
        )
    }

    /// True only when iCloud is genuinely usable: the app is provisioned with the KVS
    /// entitlement AND the user is signed into iCloud. Correctly false on an
    /// unprovisioned build, so the KVS is never initialized there.
    public var isAvailable: Bool {
        hasUbiquityEntitlement && FileManager.default.ubiquityIdentityToken != nil
    }

    /// Confirms that the host target carries the iCloud key-value-store entitlement.
    /// iOS/iPadOS apps must call this with `true` before ``start()`` because those
    /// platforms expose no public runtime entitlement inspection API. macOS continues
    /// to use its code-signature check, so configuration cannot override a missing
    /// entitlement there. Calling this after ``start()`` also retries activation.
    public func configureUbiquityKeyValueStore(entitled: Bool) {
        configuredUbiquityEntitlement = entitled
        if identityObserverTask != nil {
            activateIfAvailable()
        }
    }

    /// Begins observing iCloud availability and external changes. Idempotent; if the
    /// user signs in after launch, the store activates as soon as that identity-change
    /// notification arrives.
    public func start() {
        guard identityObserverTask == nil else { return }

        identityObserverTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: Notification.Name.NSUbiquityIdentityDidChange
            ) {
                self?.activateIfAvailable()
            }
        }
        activateIfAvailable()
    }

    private func activateIfAvailable() {
        guard activationState.consumeAvailability(isAvailable) else { return }

        // No object filter: the default KVS is the only poster of this notification, so
        // the name alone is exact — and the async sequence's `object:` wants a Sendable,
        // which `NSUbiquitousKeyValueStore` isn't.
        observerTask = Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(
                named: NSUbiquitousKeyValueStore.didChangeExternallyNotification
            ) {
                let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
                self?.broadcast(changedKeys: keys)
            }
        }
        store.synchronize()
    }

    /// Mirrors `data` to iCloud under `key`. No-op when iCloud is unavailable.
    public func mirror(_ data: Data, forKey key: String) {
        guard isAvailable else { return }

        store.set(data, forKey: key)
    }

    /// The cloud copy of `key`, or `nil` when absent or iCloud is unavailable.
    public func data(forKey key: String) -> Data? {
        guard isAvailable else { return nil }

        return store.data(forKey: key)
    }

    /// Mirrors a plist-type preference value (`String`/`Int`/`Bool`/`Data`/…) to iCloud,
    /// or clears it when `value` is nil. No-op when unavailable.
    public func mirrorObject(_ value: Any?, forKey key: String) {
        guard isAvailable else { return }

        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    /// The cloud copy of a plist-type preference value, or `nil` when absent or iCloud
    /// is unavailable.
    public func object(forKey key: String) -> Any? {
        guard isAvailable else { return nil }

        return store.object(forKey: key)
    }

    private func broadcast(changedKeys: [String]) {
        for key in changedKeys {
            NotificationCenter.default.post(
                name: Self.didChangeExternally, object: nil, userInfo: ["key": key]
            )
        }
    }
}

/// Tracks the one-way unavailable-to-available startup transition without touching
/// iCloud, keeping lifecycle behavior deterministic and independently testable.
nonisolated struct CloudSyncActivationState: Sendable {
    private(set) var hasActivated = false

    mutating func consumeAvailability(_ isAvailable: Bool) -> Bool {
        guard isAvailable, !hasActivated else { return false }
        hasActivated = true
        return true
    }
}

nonisolated enum CloudSyncEntitlementGate {
    static func allowsStore(runtimeDetected: Bool?, hostConfigured: Bool) -> Bool {
        runtimeDetected ?? hostConfigured
    }
}
