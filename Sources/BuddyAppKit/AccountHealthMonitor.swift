//
//  AccountHealthMonitor.swift
//  BuddyAppKit
//
//  A generic per-account token-health monitor (#643). Re-checks the current account's
//  token on a timer so a token revoked mid-session surfaces its "unauthorized" banner
//  without a section switch or relaunch (PadBuddy Accounts+Monitors, RankBuddy
//  AccountHealthMonitor). The apps differ only in how they probe (PadBuddy hits
//  `validateToken()`, RankBuddy hits `quota()`) and how they classify a rejection
//  (`CoderPadError.isUnauthorized` vs `HackerRankError.http(401/403)`), so the generic
//  core takes both as closures and owns the loop, the bucketing, and the verdict set.
//

import Foundation
import Observation

/// A generic `@Observable` health monitor for one account at a time. The app supplies
/// the account id to probe, an async `probe`, and an `isUnauthorized` classifier, and
/// this owns the timer, the success/unauthorized/transient bucketing, and the observable
/// verdict set the banner reads.
///
/// `AccountID` is generic (both apps key on `UUID`, but nothing here requires it) so the
/// monitor never reaches into an app account type. `@MainActor` (package default) because
/// the verdict set drives a banner.
@MainActor
@Observable
public final class AccountHealthMonitor<AccountID: Hashable & Sendable> {
    /// Accounts whose token the service has rejected since it was last checked, so the app
    /// can show the unauthorized banner for exactly these.
    public private(set) var unauthorizedAccountIDs: Set<AccountID> = []

    /// When the newest applicable check completed, or nil if none has. A stale completion
    /// from an older overlapping check does not change this timestamp.
    public private(set) var lastChecked: Date?

    /// The account to probe on each tick, evaluated fresh each time so switching the current
    /// account is picked up without restarting the loop. Returns nil to skip a tick (no
    /// current account, or one not worth probing — a mock/demo or keyless account).
    @ObservationIgnored private let accountToCheck: () -> AccountID?
    /// Probes one account's token; throws on any failure (rejection or transient).
    @ObservationIgnored private let probe: (AccountID) async throws -> Void
    /// Whether a thrown error means the token was rejected (as opposed to a transient blip).
    @ObservationIgnored private let isUnauthorized: (any Error) -> Bool
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var checkGenerations: [AccountID: UInt64] = [:]

    /// - Parameters:
    ///   - accountToCheck: The account id to probe this tick, or nil to skip.
    ///   - probe: Runs the liveness probe for that account; a light endpoint is best since
    ///     it fires on every interval (PadBuddy uses `validateToken()`, RankBuddy `quota()`).
    ///   - isUnauthorized: Classifies a thrown error as a token rejection vs a transient
    ///     failure, so only a real rejection flags the account.
    public init(accountToCheck: @escaping () -> AccountID?,
                probe: @escaping (AccountID) async throws -> Void,
                isUnauthorized: @escaping (any Error) -> Bool) {
        self.accountToCheck = accountToCheck
        self.probe = probe
        self.isUnauthorized = isUnauthorized
    }

    // Workaround: Xcode 26.5's optimizer crashes on this generic class's
    // synthesized deinit; opt this type's deinit out of optimization.
    @_optimize(none)
    deinit {}

    /// Starts the periodic check (idempotent). Checks once immediately so a key already
    /// revoked before launch surfaces the banner now rather than one interval late, then
    /// re-checks every `interval` (default 30 min).
    public func start(every interval: Duration = .seconds(1800)) {
        guard loop == nil else { return }

        let cadence = interval > .zero ? interval : .seconds(1)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                do {
                    try await Task.sleep(for: cadence)
                } catch {
                    break
                }
            }
        }
    }

    /// Stops the check loop. Kept for start/stop symmetry.
    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Probes the current account once and buckets the outcome: a success clears any prior
    /// flag, a rejection flags it, and a transient failure leaves the verdict unchanged so a
    /// blip doesn't wrongly claim the key is bad.
    public func check() async {
        guard let account = accountToCheck() else { return }
        let generation = (checkGenerations[account] ?? 0) &+ 1
        checkGenerations[account] = generation

        let outcome: CheckOutcome

        do {
            try await probe(account)
            outcome = .authorized
        } catch where isUnauthorized(error) {
            outcome = .unauthorized
        } catch {
            outcome = .transient
        }

        guard checkGenerations[account] == generation else { return }

        switch outcome {
        case .authorized:
            unauthorizedAccountIDs.remove(account)
        case .unauthorized:
            unauthorizedAccountIDs.insert(account)
        case .transient:
            break
        }
        lastChecked = Date()
    }

    /// Whether an account currently has a rejected token, so the banner can gate on it.
    public func isUnauthorized(_ accountID: AccountID) -> Bool {
        unauthorizedAccountIDs.contains(accountID)
    }

    /// Clears a stale verdict, e.g. when the account's token is edited in place; a later
    /// check re-flags it if the new token is also bad, but until then the banner shouldn't
    /// claim the new key is already bad.
    public func clearUnauthorized(_ accountID: AccountID) {
        checkGenerations[accountID] = (checkGenerations[accountID] ?? 0) &+ 1
        unauthorizedAccountIDs.remove(accountID)
    }

    private enum CheckOutcome {
        case authorized
        case unauthorized
        case transient
    }
}
