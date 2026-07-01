//
//  AccountHealthMonitorTests.swift
//  BuddyAppKitTests
//
//  The generic health monitor's success / unauthorized / transient bucketing, driven by
//  fake probe closures so no on-device service or app account type is involved.
//

import BuddyAppKit
import Foundation
import Testing

@MainActor
@Suite("Account health monitor")
struct AccountHealthMonitorTests {
    /// A stand-in for an app's classified error: `.rejected` maps to unauthorized, the
    /// rest are transient.
    private enum FakeError: Error {
        case rejected
        case offline
    }

    private static func isUnauthorized(_ error: any Error) -> Bool {
        (error as? FakeError) == .rejected
    }

    private let account = UUID()

    @Test
    func `a rejection flags the account`() async {
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in throw FakeError.rejected },
            isUnauthorized: Self.isUnauthorized
        )
        await monitor.check()
        #expect(monitor.isUnauthorized(account))
        #expect(monitor.unauthorizedAccountIDs == [account])
        #expect(monitor.lastChecked != nil)
    }

    @Test
    func `a success clears a prior flag`() async {
        var shouldReject = true
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in if shouldReject { throw FakeError.rejected } },
            isUnauthorized: Self.isUnauthorized
        )
        await monitor.check()
        #expect(monitor.isUnauthorized(account))

        shouldReject = false
        await monitor.check()
        #expect(!monitor.isUnauthorized(account))
        #expect(monitor.unauthorizedAccountIDs.isEmpty)
    }

    @Test
    func `a transient error leaves the verdict unchanged`() async {
        var error: FakeError = .rejected
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in throw error },
            isUnauthorized: Self.isUnauthorized
        )
        await monitor.check()
        #expect(monitor.isUnauthorized(account)) // flagged by the rejection

        error = .offline
        await monitor.check()
        // A transient blip must not clear the standing rejection.
        #expect(monitor.isUnauthorized(account))
    }

    @Test
    func `a skipped account (nil) is never flagged`() async {
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { nil },
            probe: { _ in throw FakeError.rejected },
            isUnauthorized: Self.isUnauthorized
        )
        await monitor.check()
        #expect(monitor.unauthorizedAccountIDs.isEmpty)
        #expect(monitor.lastChecked == nil)
    }

    @Test
    func `clearUnauthorized drops a stale verdict`() async {
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in throw FakeError.rejected },
            isUnauthorized: Self.isUnauthorized
        )
        await monitor.check()
        #expect(monitor.isUnauthorized(account))

        monitor.clearUnauthorized(account)
        #expect(!monitor.isUnauthorized(account))
    }

    @Test
    func `start is idempotent and the loop is cancellable`() async {
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in },
            isUnauthorized: Self.isUnauthorized
        )
        monitor.start(every: .seconds(1800))
        monitor.start(every: .seconds(1800)) // no-op, keeps the single loop
        // Give the immediate check a moment to run, then stop cleanly.
        try? await Task.sleep(for: .milliseconds(50))
        monitor.stop()
        #expect(monitor.lastChecked != nil) // ran once immediately
    }
}

@MainActor
@Suite("Repeating task")
struct RepeatingTaskTests {
    @MainActor private final class Counter { var value = 0 }

    @Test
    func `runs immediately then is idempotent and cancellable`() async {
        let counter = Counter()
        let loop = RepeatingTask(runImmediately: true, interval: .milliseconds(10)) {
            counter.value += 1
        }
        loop.start()
        #expect(loop.isRunning)
        loop.start() // no-op
        try? await Task.sleep(for: .milliseconds(50))
        loop.stop()
        #expect(!loop.isRunning)
        #expect(counter.value >= 1) // the immediate run happened
    }

    @Test
    func `runImmediately false defers the first run past the initial interval`() async {
        let counter = Counter()
        let loop = RepeatingTask(runImmediately: false, interval: .seconds(60)) {
            counter.value += 1
        }
        loop.start()
        // Well within the 60s interval: with no immediate run, nothing has fired yet.
        try? await Task.sleep(for: .milliseconds(50))
        loop.stop()
        #expect(counter.value == 0)
    }
}
