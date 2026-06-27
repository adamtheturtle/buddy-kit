//
//  RefreshScheduleTests.swift
//  BuddyAppKitTests
//
//  Ported from the coderpad pad-list-logic suite: the wall-clock refresh grid.
//

import BuddyAppKit
import Testing

@Suite("Refresh schedule (wall-clock grid)")
struct RefreshScheduleTests {
    let clock = ContinuousClock()

    @Test
    func `fires one interval after the anchor when caught up`() {
        let anchor = clock.now
        let fire = RefreshSchedule.nextFire(after: anchor, interval: .seconds(10), now: anchor)
        #expect(fire == anchor.advanced(by: .seconds(10)))
    }

    @Test
    func `realigns to the next future boundary after a long gap, no burst`() {
        let anchor = clock.now
        // 25s elapsed since the anchor on a 10s grid: boundaries at +10 and +20 are
        // already past, so the next fire is the +30 boundary (not a catch-up burst).
        let now = anchor.advanced(by: .seconds(25))
        let fire = RefreshSchedule.nextFire(after: anchor, interval: .seconds(10), now: now)
        #expect(fire == anchor.advanced(by: .seconds(30)))
    }

    @Test
    func `next fire is always strictly in the future`() {
        let anchor = clock.now
        for elapsed in [0, 3, 9, 10, 11, 100] {
            let now = anchor.advanced(by: .seconds(elapsed))
            let fire = RefreshSchedule.nextFire(after: anchor, interval: .seconds(10), now: now)
            #expect(fire > now)
        }
    }

    @Test
    func `a non-positive interval still advances`() {
        let now = clock.now
        let fire = RefreshSchedule.nextFire(after: now, interval: .zero, now: now)
        #expect(fire > now)
    }

    /// MainActor-isolated counter so the closures below mutate shared reference state
    /// instead of a captured `var` (which an escaping `@Sendable` task closure can't).
    @MainActor private final class RunCounter { var value = 0 }

    /// Cross-module isolation contract (the reason for the `isolation` parameter): a
    /// `@MainActor` caller must be able to hand `periodicReload` closures that read and
    /// mutate MainActor state without a region-isolation / `Sendable` error. This is
    /// primarily a *compile-time* guard — if the signature ever regresses to `nonisolated`
    /// closures, this test stops building. The Xcode Cloud build failed exactly here,
    /// seeing `periodicReload` as nonisolated across the module boundary.
    @MainActor
    @Test
    func `runs caller-isolated closures reading MainActor state`() async {
        let counter = RunCounter()
        let task = Task { @MainActor in
            await periodicReload(interval: { .milliseconds(10) }, work: {
                counter.value += 1
            })
        }
        // The first `work` runs immediately, before any sleep; give it time, then stop
        // the loop and wait for it to unwind so the count is settled.
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
        #expect(counter.value >= 1)
    }
}
