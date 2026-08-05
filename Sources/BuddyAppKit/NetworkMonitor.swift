//
//  NetworkMonitor.swift
//  BuddyAppKit
//
//  Observes system network reachability so an app can drop into a read-only mode
//  while there's no path to its service. Reusing the same visual language as a
//  revoked key (a banner plus disabled editing controls), an offline app reads as
//  "browse only" rather than letting edits fail one failed request at a time (#321).
//

import Foundation
import Network
import Synchronization

nonisolated final class NetworkStatusCoalescer: Sendable {
    private struct State: Sendable {
        var generation: UInt64 = 0
        var isOffline = false
    }

    private let state = Mutex(State())

    func enqueue(isOffline: Bool) -> UInt64 {
        state.withLock { state in
            state.generation &+= 1
            state.isOffline = isOffline
            return state.generation
        }
    }

    func value(ifCurrent generation: UInt64) -> Bool? {
        state.withLock { state in
            guard state.generation == generation else { return nil }

            return state.isOffline
        }
    }
}

@Observable
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    /// True when the system reports no satisfied network path, so the app can't reach
    /// its service and goes read-only. Defaults to `false` (online): a not-yet-started
    /// or just-launched monitor never falsely locks the UI before the first path update.
    public private(set) var isOffline = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.adamdangoor.buddyappkit.network-monitor")
    @ObservationIgnored private let statusCoalescer = NetworkStatusCoalescer()
    @ObservationIgnored private var started = false

    private init() {}

    /// Begins watching the default network path. Idempotent: repeated calls keep the
    /// single existing monitor, mirroring the other launch-time monitors. Path updates
    /// arrive on a background queue, so the observable flag is set back on the main
    /// actor where the UI reads it.
    public func start() {
        guard !started else { return }

        started = true
        let statusCoalescer = statusCoalescer
        monitor.pathUpdateHandler = { [weak self, statusCoalescer] path in
            let generation = statusCoalescer.enqueue(isOffline: path.status != .satisfied)
            Task { @MainActor in
                guard let self,
                      let offline = statusCoalescer.value(ifCurrent: generation),
                      self.isOffline != offline else { return }

                self.isOffline = offline
            }
        }
        monitor.start(queue: queue)
    }
}
