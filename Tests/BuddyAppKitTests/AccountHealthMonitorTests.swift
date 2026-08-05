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
    func `an older rejection cannot overwrite a newer success`() async {
        let probes = ControlledProbes()
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in try await probes.run() },
            isUnauthorized: Self.isUnauthorized
        )

        let older = Task { await monitor.check() }
        await probes.waitUntilStarted(1)
        let newer = Task { await monitor.check() }
        await probes.waitUntilStarted(2)

        await probes.succeed(1)
        await newer.value
        await probes.fail(0, with: FakeError.rejected)
        await older.value

        #expect(!monitor.isUnauthorized(account))
    }

    @Test
    func `an older success cannot clear a newer rejection`() async {
        let probes = ControlledProbes()
        let monitor = AccountHealthMonitor<UUID>(
            accountToCheck: { self.account },
            probe: { _ in try await probes.run() },
            isUnauthorized: Self.isUnauthorized
        )

        let older = Task { await monitor.check() }
        await probes.waitUntilStarted(1)
        let newer = Task { await monitor.check() }
        await probes.waitUntilStarted(2)

        await probes.fail(1, with: FakeError.rejected)
        await newer.value
        await probes.succeed(0)
        await older.value

        #expect(monitor.isUnauthorized(account))
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

private actor ControlledProbes {
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var startedCount = 0

    func run() async throws {
        let index = startedCount
        startedCount += 1
        try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while startedCount < count {
            await Task.yield()
        }
    }

    func succeed(_ index: Int) {
        continuations.removeValue(forKey: index)?.resume()
    }

    func fail(_ index: Int, with error: any Error) {
        continuations.removeValue(forKey: index)?.resume(throwing: error)
    }
}
