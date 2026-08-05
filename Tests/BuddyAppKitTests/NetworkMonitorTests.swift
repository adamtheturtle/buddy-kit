//
//  NetworkMonitorTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

struct NetworkMonitorTests {
    @Test("reordered path delivery cannot publish a stale status")
    func reorderedDeliveryDropsStaleStatus() {
        let coalescer = NetworkStatusCoalescer()
        let offlineGeneration = coalescer.enqueue(isOffline: true)
        let onlineGeneration = coalescer.enqueue(isOffline: false)

        #expect(coalescer.value(ifCurrent: onlineGeneration) == false)
        #expect(coalescer.value(ifCurrent: offlineGeneration) == nil)
    }
}
