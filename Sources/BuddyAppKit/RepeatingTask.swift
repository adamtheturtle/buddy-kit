//
//  RepeatingTask.swift
//  BuddyAppKit
//
//  A reusable poll-loop primitive (#643). Captures the `guard task == nil` idempotent
//  start, the "run now (optionally), then sleep-and-repeat until cancelled" body, and
//  the stop() that both apps hand-rolled across four monitors (PadBuddy's background
//  pad refresher + health monitor, RankBuddy's liveness monitor + health monitor). The
//  loop body reuses ``periodicReload`` so the wall-clock grid (no drift, no catch-up
//  burst) is shared rather than re-implemented as a naive `sleep` loop.
//

import Foundation

/// Owns a single repeating background task: starts idempotently, runs `work` on an
/// interval until cancelled, and stops cleanly. The scaffold copy-pasted across both
/// apps' monitors, in one place.
///
/// `@MainActor` (the package default) because the callers are `@Observable` monitors
/// whose `work` closures mutate view-facing state; the loop runs on the MainActor via
/// ``periodicReload``'s `#isolation`, so `work` reads and writes that state without a
/// `Sendable` hop.
@MainActor
public final class RepeatingTask {
    private let runImmediately: Bool
    private let interval: () -> Duration
    private let work: () async -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - runImmediately: Whether to run `work` once as soon as the loop starts, before
    ///     the first sleep. `true` for a health check (surface a revoked key now, not one
    ///     interval late); `false` for a background refresher whose first useful tick is
    ///     one interval out because launch already loaded the data.
    ///   - interval: The cadence, recomputed after each run so a caller can stretch it
    ///     from a live setting (RankBuddy re-reads the configured sweep minutes each tick).
    ///   - work: The unit of work to run each tick.
    public init(runImmediately: Bool,
                interval: @escaping () -> Duration,
                work: @escaping () async -> Void) {
        self.runImmediately = runImmediately
        self.interval = interval
        self.work = work
    }

    /// Convenience for a fixed cadence.
    public convenience init(runImmediately: Bool,
                            interval: Duration,
                            work: @escaping () async -> Void) {
        self.init(runImmediately: runImmediately, interval: { interval }, work: work)
    }

    /// Whether the loop is currently running, so tests (and callers) can assert idempotency.
    public var isRunning: Bool { task != nil }

    /// Starts the loop. Idempotent: a second call while already running is a no-op and
    /// keeps the single existing task, matching every hand-rolled `guard task == nil`.
    public func start() {
        guard task == nil else { return }

        // Capture the closures into locals so the task body doesn't retain `self` for the
        // sole purpose of reaching them; `periodicReload` runs on this actor via #isolation.
        let runImmediately = runImmediately
        let interval = interval
        let work = work
        task = Task {
            if !runImmediately {
                // Delay the first run by one interval: skip the immediate `work` in
                // periodicReload by sleeping first, then hand it the steady loop.
                let clock = ContinuousClock()
                do {
                    try await clock.sleep(for: interval())
                } catch {
                    return
                }
            }
            await periodicReload(interval: interval, work: work)
        }
    }

    /// Cancels the loop and clears the stored task, so a later `start()` begins fresh.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
