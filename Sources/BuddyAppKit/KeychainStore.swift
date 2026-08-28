//
//  KeychainStore.swift
//  BuddyAppKit
//
//  Generic-password Keychain access with the service name injected, so each app that
//  reuses it pins its own service string (#512). Lifted from the coderpad app; the
//  legacy-keychain rationale below is preserved verbatim because it's load-bearing.
//

import Foundation
import os
import Security

/// Distinguishes an absent Keychain item from failures that must not be treated as
/// an empty store (for example locked interaction or a missing entitlement).
public nonisolated enum KeychainReadResult: Sendable, Equatable {
    case value(Data)
    case notFound
    case failure(OSStatus)

    var allowsEmptyStoreMigration: Bool {
        self == .notFound
    }

    /// Whether an empty accounts snapshot that follows this read may be published —
    /// which, for an empty snapshot, means deleting the stored item.
    ///
    /// Only when the read actually told us the store is empty. A `.failure` yields an
    /// empty array too, and the Observation macro fires the store's `accounts`
    /// observer during `init`, so publishing it deleted the item holding every
    /// configured account and API key on the next launch after a locked keychain, a
    /// denied access prompt, or a truncated item (#4726).
    public var allowsDeletingStore: Bool {
        switch self {
        case .value, .notFound: true
        case .failure: false
        }
    }

    static func classify(status: OSStatus, data: Data?) -> Self {
        switch status {
        case errSecSuccess:
            data.map(Self.value) ?? .failure(errSecDecode)
        case errSecItemNotFound:
            .notFound
        default:
            .failure(status)
        }
    }
}

public nonisolated struct KeychainStore: Sendable {
    /// The Keychain service the items are stored under. INJECTED, and a hard
    /// compatibility contract: an app must keep the same string forever or existing
    /// users lose every saved item (the items are keyed by it).
    public let service: String
    private let logger: Logger

    public init(service: String, logger: Logger) {
        self.service = service
        self.logger = logger
    }

    private func baseQuery(account: String) -> [String: Any] {
        // Deliberately the legacy (file-based) keychain — NOT the data-protection keychain
        // (`kSecUseDataProtectionKeychain`). On macOS the data-protection keychain needs a
        // keychain-access-group entitlement (Keychain Sharing) or a profile's
        // application-identifier to be usable at all; this app is sandboxed but embeds no
        // profile and can't declare keychain-access-groups — that entitlement made AMFI
        // refuse to launch the notarized build (the "can't be opened" bug, see #451). With
        // neither, every data-protection SecItemAdd failed with errSecMissingEntitlement
        // (-34018, verified), silently dropping every saved account across launches (#460).
        // The legacy keychain needs no such entitlement and works for a sandboxed,
        // profile-less app. Trade-off: a Debug *rebuild* changes the code signature and so
        // re-prompts for keychain access; a stable notarized build never does.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func read(account: String) -> KeychainReadResult {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let result = KeychainReadResult.classify(status: status, data: item as? Data)
        if case let .failure(status) = result {
            logger.error(
                "Keychain SecItemCopyMatching failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
        }
        return result
    }

    /// Compatibility convenience for consumers that intentionally treat every failure
    /// as absence. Persistence owners should use ``read(account:)`` instead.
    public func readData(account: String) -> Data? {
        guard case let .value(data) = read(account: account) else { return nil }
        return data
    }

    /// Returns whether the write actually reached the Keychain. Failures are logged
    /// here, but callers that own user-visible state (e.g. ``KeychainAccountStore``)
    /// should also surface them: a dropped write silently reverts the user's changes
    /// on the next launch.
    @discardableResult
    public func write(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error(
                    "Keychain SecItemAdd failed for account '\(account, privacy: .public)' (OSStatus \(addStatus))"
                )
                return false
            }
        } else if status != errSecSuccess {
            logger.error(
                "Keychain SecItemUpdate failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
            return false
        }
        return true
    }

    /// Returns whether the item is gone afterwards; deleting an item that never
    /// existed counts as success.
    @discardableResult
    public func delete(account: String) -> Bool {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logger.error(
                "Keychain SecItemDelete failed for account '\(account, privacy: .public)' (OSStatus \(status))"
            )
            return false
        }
        return true
    }
}
