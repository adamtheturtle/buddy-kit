//
//  KeychainAccountStore.swift
//  BuddyAppKit
//
//  A generic multi-account store backed by the Keychain (accounts) + UserDefaults
//  (selection and the merged-view opt-in), extracted from the coderpad app (#513) so a
//  sibling app can reuse it. All app-specific behaviour — serialization, widget
//  mirroring, cache teardown on remove/rekey, the testing seed, legacy migration — is
//  injected through ``Config``, so this type knows nothing about any particular service.
//

import Foundation
import os
import Security

/// The minimum an account model must provide to live in ``KeychainAccountStore``.
/// Deliberately requires only two nonisolated members — NOT `Codable`/`Hashable`/
/// `Identifiable` — so a MainActor-default app whose model has main-actor-isolated
/// conformances can still satisfy it. Serialization is injected through ``Config``
/// (and runs on the main actor, where the model's `Codable` lives) instead.
public protocol StorableAccount {
    /// The account's stable per-device identifier.
    var accountID: UUID { get }
    /// Whether `self` talks to a different backend than `other` (a changed key or
    /// server), so the store can fire `onRekeyed` to invalidate now-stale caches.
    func pointsAtDifferentBackend(than other: Self) -> Bool
}

@Observable
@MainActor
public final class KeychainAccountStore<Account: StorableAccount> {
    // Workaround: Xcode 26.5's optimizer crashes on this generic @Observable
    // class's synthesized deinit; opt this type's deinit out of optimization.
    @_optimize(none)
    deinit {}

    /// The injected serialization, side-effects, and storage keys that adapt the generic
    /// store to a particular app. Closures run on the main actor (the store is
    /// main-actor bound), so the account model's main-actor-isolated `Codable` is usable
    /// inside `encode`/`decode`.
    public struct Config {
        public var keychain: KeychainStore
        public var accountsKey: String
        public var currentIDDefaultsKey: String
        public var showAllAccountsDefaultsKey: String
        public var encode: @MainActor ([Account]) -> Data?
        public var decode: @MainActor (Data) -> [Account]
        /// True under the app's UI-testing launch: the store seeds from `seedForTesting`
        /// and skips ALL persistence, so tests run from a deterministic state and never
        /// touch real accounts or the login keychain.
        public var isTestingMode: Bool
        public var seedForTesting: @MainActor () -> [Account]
        /// One-time migration from older storage, run only when no accounts load and not
        /// testing. Returns the migrated accounts (and performs its own cleanup), or nil.
        public var migrateIfEmpty: @MainActor () -> [Account]?
        public var onAccountsChanged: @MainActor ([Account]) -> Void
        public var onCurrentChanged: @MainActor (Account?) -> Void
        /// Receives the removed account itself (not just its id): app caches keyed
        /// by the account's credentials (server + API key) can only be purged with
        /// the full value in hand.
        public var onRemoved: @MainActor (Account) -> Void
        /// Receives the account's *previous* value, whose old credentials the app
        /// must purge; the updated value is already in `accounts`.
        public var onRekeyed: @MainActor (Account) -> Void
        public var logger: Logger
        /// Reports completion of each asynchronous accounts Keychain mutation on the main actor.
        public var onPersistenceResult: @MainActor (Bool) -> Void
        /// Injectable typed read used at startup. The default reads the configured Keychain.
        public var readAccounts: @MainActor (KeychainStore, String) -> KeychainReadResult
        /// Surfaces a startup Keychain failure so the host can present recovery UI.
        public var onReadFailure: @MainActor (OSStatus) -> Void

        public init(
            keychain: KeychainStore,
            accountsKey: String,
            currentIDDefaultsKey: String,
            showAllAccountsDefaultsKey: String,
            encode: @escaping @MainActor ([Account]) -> Data?,
            decode: @escaping @MainActor (Data) -> [Account],
            isTestingMode: Bool,
            seedForTesting: @escaping @MainActor () -> [Account],
            migrateIfEmpty: @escaping @MainActor () -> [Account]?,
            onAccountsChanged: @escaping @MainActor ([Account]) -> Void,
            onCurrentChanged: @escaping @MainActor (Account?) -> Void,
            onRemoved: @escaping @MainActor (Account) -> Void,
            onRekeyed: @escaping @MainActor (Account) -> Void,
            logger: Logger,
            onPersistenceResult: @escaping @MainActor (Bool) -> Void = { _ in },
            readAccounts: @escaping @MainActor (KeychainStore, String) -> KeychainReadResult = {
                $0.read(account: $1)
            },
            onReadFailure: @escaping @MainActor (OSStatus) -> Void = { _ in }
        ) {
            self.keychain = keychain
            self.accountsKey = accountsKey
            self.currentIDDefaultsKey = currentIDDefaultsKey
            self.showAllAccountsDefaultsKey = showAllAccountsDefaultsKey
            self.encode = encode
            self.decode = decode
            self.isTestingMode = isTestingMode
            self.seedForTesting = seedForTesting
            self.migrateIfEmpty = migrateIfEmpty
            self.onAccountsChanged = onAccountsChanged
            self.onCurrentChanged = onCurrentChanged
            self.onRemoved = onRemoved
            self.onRekeyed = onRekeyed
            self.logger = logger
            self.onPersistenceResult = onPersistenceResult
            self.readAccounts = readAccounts
            self.onReadFailure = onReadFailure
        }
    }

    public var accounts: [Account] {
        didSet {
            let repaired = Self.repairDuplicateAccountIDs(accounts)
            if repaired.count != accounts.count {
                accounts = repaired
            }
            persistAccounts()
            // Pass `accounts` directly — never the shared singleton — since the
            // Observation macro fires this observer during init too, where reaching back
            // into the still-initializing singleton would deadlock.
            config.onAccountsChanged(accounts)
        }
    }

    public var currentAccountID: UUID? {
        didSet {
            persistCurrentID()
            // Hand the resolved current account (computed from self, not the singleton)
            // to the app so it can repaint the widget; safe during init for the same
            // reason as above.
            config.onCurrentChanged(currentAccount)
        }
    }

    public var currentAccount: Account? {
        guard let id = currentAccountID else { return accounts.first }

        return accounts.first { $0.accountID == id } ?? accounts.first
    }

    /// Whether the user opted into the combined "All Accounts" view. Only *honoured*
    /// when it makes sense (see ``isMergedView``), so a single-account user who once
    /// enabled it silently falls back to that account.
    public var showAllAccounts = false {
        didSet { persistShowAllAccounts() }
    }

    /// Every configured account, eligible to be merged.
    public var mergeableAccounts: [Account] {
        accounts
    }

    /// Whether the combined view is actually active: opted in *and* at least two
    /// accounts to merge. Everything that branches on merged mode reads this.
    public var isMergedView: Bool {
        showAllAccounts && mergeableAccounts.count >= 2
    }

    /// True while the latest accounts snapshot failed to reach the Keychain, so the
    /// app can warn that in-memory changes will revert on relaunch instead of
    /// silently losing them. The in-memory `accounts` array itself is the retryable
    /// dirty state: ``retryPersistence()`` re-enqueues it, and any subsequent
    /// successful write (every mutation rewrites the full snapshot) clears the flag.
    public private(set) var persistenceFailed = false
    /// The OSStatus from a failed startup read, or nil when the item loaded or was absent.
    public private(set) var readFailureStatus: OSStatus?

    @ObservationIgnored private let config: Config
    @ObservationIgnored private let writeQueue = SerialWriteQueue()
    @ObservationIgnored private var persistenceResults = PersistenceResultState()
    /// Set when the launch read failed for a reason other than the item being absent.
    ///
    /// A failed read yields an empty `accounts`, and the Observation macro fires the
    /// `accounts` observer during `init` — so `persistAccounts()` saw an empty array
    /// and enqueued a delete of the Keychain item holding every configured account and
    /// API key. A locked login keychain, a denied access prompt after a Debug rebuild,
    /// `errSecDecode` from a truncated item: any of them wiped the user's accounts on
    /// the next launch, and the deliberate suppression of empty-store migration was
    /// defeated by the deletion that followed it. While this stands, an *empty*
    /// snapshot is never published; it did not come from the user removing anything.
    /// Cleared by the first non-empty write — an explicit add — after which a genuine
    /// removal deletes as normal.
    @ObservationIgnored private var launchReadFailed = false

    public init(config: Config) {
        self.config = config
        if config.isTestingMode {
            accounts = Self.repairDuplicateAccountIDs(config.seedForTesting())
            currentAccountID = accounts.first?.accountID
            return
        }
        let readResult = config.readAccounts(config.keychain, config.accountsKey)
        launchReadFailed = !readResult.allowsDeletingStore
        let stored: [Account]
        switch readResult {
        case let .value(data):
            stored = config.decode(data)
        case .notFound:
            stored = []
        case let .failure(status):
            stored = []
            readFailureStatus = status
            config.onReadFailure(status)
        }
        let loaded = Self.repairDuplicateAccountIDs(stored)
        var shouldPersistRepair = loaded.count != stored.count
        accounts = loaded
        if let stored = UserDefaults.standard.string(forKey: config.currentIDDefaultsKey),
           let uuid = UUID(uuidString: stored),
           loaded.contains(where: { $0.accountID == uuid }) {
            currentAccountID = uuid
        } else {
            currentAccountID = loaded.first?.accountID
        }

        if readResult.allowsEmptyStoreMigration,
           loaded.isEmpty,
           let migrated = config.migrateIfEmpty(),
           !migrated.isEmpty {
            let repairedMigration = Self.repairDuplicateAccountIDs(migrated)
            accounts = repairedMigration
            currentAccountID = repairedMigration.first?.accountID
            shouldPersistRepair = shouldPersistRepair || repairedMigration.count != migrated.count
        }
        showAllAccounts = UserDefaults.standard.bool(forKey: config.showAllAccountsDefaultsKey)
        if shouldPersistRepair {
            persistAccounts()
        }
    }

    /// Adds an account unless its ID already exists. Duplicate IDs are rejected so all
    /// selection, update, removal, and callback operations remain one-to-one.
    @discardableResult
    public func add(_ account: Account) -> Bool {
        guard !accounts.contains(where: { $0.accountID == account.accountID }) else { return false }

        accounts.append(account)
        if currentAccountID == nil { currentAccountID = account.accountID }
        return true
    }

    public func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.accountID == account.accountID }) else { return }

        let previous = accounts[index]
        accounts[index] = account
        // A changed key or server points at potentially different data (even a different
        // org), so the app's caches keyed by this account no longer apply. Hand over the
        // previous value: caches keyed by the old credentials need them to purge.
        if account.pointsAtDifferentBackend(than: previous) {
            config.onRekeyed(previous)
        }
    }

    public func remove(id: UUID) {
        // Captured before removal so the hook receives the full account — there's
        // nothing to tear down when the id was never stored.
        let removed = accounts.first { $0.accountID == id }
        accounts.removeAll { $0.accountID == id }
        if currentAccountID == id {
            currentAccountID = accounts.first?.accountID
        }
        if let removed {
            config.onRemoved(removed)
        }
    }

    /// Keeps the last snapshot for each ID and preserves the relative order of those
    /// winners, repairing historical duplicate arrays deterministically.
    static func repairDuplicateAccountIDs(_ accounts: [Account]) -> [Account] {
        var seen: Set<UUID> = []
        return Array(accounts.reversed().filter { seen.insert($0.accountID).inserted }.reversed())
    }

    private func persistAccounts() {
        guard !config.isTestingMode else { return }

        // An empty snapshot after a failed launch read is not a removal, and deleting
        // on the strength of it destroys every stored credential (#4726). The read
        // failure is already surfaced through `readFailureStatus`.
        if accounts.isEmpty, launchReadFailed {
            config.logger.error("Refusing to delete the stored accounts after a failed Keychain read")
            return
        }

        let keychain = config.keychain
        let key = config.accountsKey
        let generation = persistenceResults.schedule()
        // Encode on the main actor (where the account model's Codable conformance lives),
        // then hand only the resulting `Data` to the background write — so the account
        // model never has to cross actors. Writes stay ordered via the queue so a slower
        // earlier write can't overwrite a newer snapshot.
        if accounts.isEmpty {
            writeQueue.enqueue(priority: .userInitiated) { [weak self] in
                let succeeded = keychain.delete(account: key)
                Task { @MainActor in
                    self?.applyPersistenceResult(succeeded, generation: generation)
                }
            }
            return
        }
        // A non-empty snapshot supersedes whatever could not be read, so a later
        // removal is a genuine one.
        launchReadFailed = false
        guard let data = config.encode(accounts) else {
            config.logger.error("Failed to encode accounts snapshot")
            if persistenceResults.apply(succeeded: false, generation: generation) {
                persistenceFailed = persistenceResults.failed
            }
            return
        }

        writeQueue.enqueue(priority: .userInitiated) { [weak self] in
            let succeeded = keychain.write(data, account: key)
            // Surface the outcome on the main actor: a failed write means the edit
            // the UI just accepted will revert on relaunch, which the store must
            // not keep to itself.
            Task { @MainActor in
                self?.applyPersistenceResult(succeeded, generation: generation)
            }
        }
    }

    private func applyPersistenceResult(_ succeeded: Bool, generation: UInt64) {
        guard persistenceResults.apply(succeeded: succeeded, generation: generation) else { return }

        persistenceFailed = persistenceResults.failed
        config.onPersistenceResult(succeeded)
    }

    /// Re-enqueues the current in-memory accounts snapshot after a failed write.
    /// The snapshot is always whole (every mutation rewrites the full array), so
    /// retrying persists everything that accumulated since the failure.
    public func retryPersistence() {
        persistAccounts()
    }

    private func persistCurrentID() {
        guard !config.isTestingMode else { return }

        if let id = currentAccountID {
            UserDefaults.standard.set(id.uuidString, forKey: config.currentIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: config.currentIDDefaultsKey)
        }
    }

    private func persistShowAllAccounts() {
        guard !config.isTestingMode else { return }

        UserDefaults.standard.set(showAllAccounts, forKey: config.showAllAccountsDefaultsKey)
    }
}

nonisolated struct PersistenceResultState: Sendable {
    private var currentGeneration: UInt64 = 0
    private(set) var failed = false

    mutating func schedule() -> UInt64 {
        currentGeneration &+= 1
        return currentGeneration
    }

    @discardableResult
    mutating func apply(succeeded: Bool, generation: UInt64) -> Bool {
        guard generation == currentGeneration else { return false }
        failed = !succeeded
        return true
    }
}
