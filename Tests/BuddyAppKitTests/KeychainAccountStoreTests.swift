//
//  KeychainAccountStoreTests.swift
//  BuddyAppKitTests
//
//  Deterministic, UI-free coverage of the generic account store's in-memory logic
//  (#513): the testing-mode seed, selection resolution, add/update/remove, the
//  rekey/remove hooks, and the merged-view rule. Runs in testing mode so it never
//  touches the real Keychain or UserDefaults.
//

@testable import BuddyAppKit
import Foundation
import os
import Security
import Testing

private struct MockAccount: StorableAccount, Equatable {
    let accountID: UUID
    var key: String

    func pointsAtDifferentBackend(than other: MockAccount) -> Bool {
        key != other.key
    }
}

@MainActor
private func makeStore(
    seed: [MockAccount],
    onAccountsChanged: @escaping @MainActor ([MockAccount]) -> Void = { _ in },
    onRemoved: @escaping @MainActor (MockAccount) -> Void = { _ in },
    onRekeyed: @escaping @MainActor (MockAccount) -> Void = { _ in }
) -> KeychainAccountStore<MockAccount> {
    let config = KeychainAccountStore<MockAccount>.Config(
        keychain: KeychainStore(service: "test.buddyappkit.unused", logger: Logger(subsystem: "test", category: "x")),
        accountsKey: "accounts",
        currentIDDefaultsKey: "current",
        showAllAccountsDefaultsKey: "showAll",
        encode: { _ in nil },
        decode: { _ in [] },
        isTestingMode: true,
        seedForTesting: { seed },
        migrateIfEmpty: { nil },
        onAccountsChanged: onAccountsChanged,
        onCurrentChanged: { _ in },
        onRemoved: onRemoved,
        onRekeyed: onRekeyed,
        logger: Logger(subsystem: "test", category: "x")
    )
    return KeychainAccountStore(config: config)
}

@Suite("KeychainAccountStore in-memory logic")
@MainActor
struct KeychainAccountStoreTests {
    @Test
    nonisolated func `keychain statuses distinguish absence from read failures`() {
        let data = Data([1, 2, 3])

        #expect(KeychainReadResult.classify(status: errSecSuccess, data: data) == .value(data))
        #expect(KeychainReadResult.classify(status: errSecSuccess, data: nil) == .failure(errSecDecode))
        #expect(KeychainReadResult.classify(status: errSecItemNotFound, data: nil) == .notFound)
        #expect(KeychainReadResult.classify(
            status: errSecInteractionNotAllowed, data: nil
        ) == .failure(errSecInteractionNotAllowed))
        #expect(KeychainReadResult.classify(
            status: errSecMissingEntitlement, data: nil
        ) == .failure(errSecMissingEntitlement))
        #expect(KeychainReadResult.notFound.allowsEmptyStoreMigration)
        #expect(!KeychainReadResult.failure(errSecInteractionNotAllowed).allowsEmptyStoreMigration)
    }

    @Test
    func `startup read failure is surfaced and cannot trigger migration`() {
        var migrationRan = false
        var reportedStatus: OSStatus?
        let unique = UUID().uuidString
        let config = KeychainAccountStore<MockAccount>.Config(
            keychain: KeychainStore(
                service: "test.buddyappkit.unused", logger: Logger(subsystem: "test", category: "x")
            ),
            accountsKey: "accounts",
            currentIDDefaultsKey: "current-\(unique)",
            showAllAccountsDefaultsKey: "showAll-\(unique)",
            encode: { _ in nil },
            decode: { _ in [] },
            isTestingMode: false,
            seedForTesting: { [] },
            migrateIfEmpty: {
                migrationRan = true
                return []
            },
            onAccountsChanged: { _ in },
            onCurrentChanged: { _ in },
            onRemoved: { _ in },
            onRekeyed: { _ in },
            logger: Logger(subsystem: "test", category: "x"),
            readAccounts: { _, _ in .failure(errSecInteractionNotAllowed) },
            onReadFailure: { reportedStatus = $0 }
        )

        let store = KeychainAccountStore(config: config)

        #expect(store.accounts.isEmpty)
        #expect(store.readFailureStatus == errSecInteractionNotAllowed)
        #expect(reportedStatus == errSecInteractionNotAllowed)
        #expect(!migrationRan)
    }

    @Test
    nonisolated func `older persistence completions cannot replace the latest result`() {
        var results = PersistenceResultState()
        let older = results.schedule()
        let newer = results.schedule()

        let newerApplied = results.apply(succeeded: true, generation: newer)
        #expect(newerApplied)
        #expect(!results.failed)
        let olderFailureApplied = results.apply(succeeded: false, generation: older)
        #expect(!olderFailureApplied)
        #expect(!results.failed)

        let latest = results.schedule()
        let latestApplied = results.apply(succeeded: false, generation: latest)
        #expect(latestApplied)
        #expect(results.failed)
        let olderSuccessApplied = results.apply(succeeded: true, generation: newer)
        #expect(!olderSuccessApplied)
        #expect(results.failed)
    }

    @Test
    func `testing mode seeds the accounts and selects the first`() {
        let a = MockAccount(accountID: UUID(), key: "a")
        let store = makeStore(seed: [a])
        #expect(store.accounts.count == 1)
        #expect(store.currentAccountID == a.accountID)
        #expect(store.currentAccount == a)
    }

    @Test
    func `add appends and selects when nothing is current`() {
        let store = makeStore(seed: [])
        #expect(store.currentAccountID == nil)

        let a = MockAccount(accountID: UUID(), key: "a")
        store.add(a)
        #expect(store.accounts == [a])
        #expect(store.currentAccountID == a.accountID)
    }

    @Test
    func `add rejects a duplicate account id`() {
        let id = UUID()
        let original = MockAccount(accountID: id, key: "original")
        let duplicate = MockAccount(accountID: id, key: "duplicate")
        let store = makeStore(seed: [original])

        #expect(!store.add(duplicate))
        #expect(store.accounts == [original])
    }

    @Test
    func `loaded duplicate ids keep the last snapshot and remain one-to-one`() {
        let duplicateID = UUID()
        let survivor = MockAccount(accountID: UUID(), key: "survivor")
        let repaired = KeychainAccountStore<MockAccount>.repairDuplicateAccountIDs([
            MockAccount(accountID: duplicateID, key: "old"),
            survivor,
            MockAccount(accountID: duplicateID, key: "new")
        ])

        #expect(repaired == [survivor, MockAccount(accountID: duplicateID, key: "new")])

        let store = makeStore(seed: repaired)
        store.update(MockAccount(accountID: duplicateID, key: "updated"))
        #expect(store.accounts.count(where: { $0.accountID == duplicateID }) == 1)
        #expect(store.accounts.last?.key == "updated")

        store.remove(id: duplicateID)
        #expect(store.accounts == [survivor])
    }

    @Test
    func `assigning duplicate ids publishes the repaired snapshot`() {
        let duplicateID = UUID()
        let old = MockAccount(accountID: duplicateID, key: "old")
        let new = MockAccount(accountID: duplicateID, key: "new")
        let survivor = MockAccount(accountID: UUID(), key: "survivor")
        var published: [[MockAccount]] = []
        let store = makeStore(seed: [], onAccountsChanged: { published.append($0) })

        store.accounts = [old, survivor, new]

        #expect(store.accounts == [survivor, new])
        #expect(published.last == [survivor, new])
    }

    @Test
    func `update fires onRekeyed only when the backend changes`() {
        let id = UUID()
        var rekeyed: [MockAccount] = []
        let store = makeStore(seed: [MockAccount(accountID: id, key: "a")], onRekeyed: { rekeyed.append($0) })

        store.update(MockAccount(accountID: id, key: "a")) // same key → no rekey
        #expect(rekeyed.isEmpty)

        store.update(MockAccount(accountID: id, key: "b")) // changed key → rekey
        // The hook receives the *previous* value: the old credentials are what
        // credential-keyed caches need to purge.
        #expect(rekeyed == [MockAccount(accountID: id, key: "a")])
    }

    @Test
    func `remove drops the account, reselects, and fires onRemoved`() {
        let first = MockAccount(accountID: UUID(), key: "a")
        let second = MockAccount(accountID: UUID(), key: "b")
        var removed: [MockAccount] = []
        let store = makeStore(seed: [first, second], onRemoved: { removed.append($0) })

        store.remove(id: first.accountID)
        #expect(store.accounts == [second])
        #expect(store.currentAccountID == second.accountID) // reselected the survivor
        #expect(removed == [first])

        store.remove(id: first.accountID) // unknown id → no teardown to run
        #expect(removed == [first])
    }

    @Test
    func `merged view needs the opt-in and at least two accounts`() {
        let store = makeStore(seed: [MockAccount(accountID: UUID(), key: "a")])
        store.showAllAccounts = true
        #expect(!store.isMergedView) // opted in but only one account

        store.add(MockAccount(accountID: UUID(), key: "b"))
        #expect(store.isMergedView)
    }
}
