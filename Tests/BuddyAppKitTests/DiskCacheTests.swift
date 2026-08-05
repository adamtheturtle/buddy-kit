//
//  DiskCacheTests.swift
//  BuddyAppKitTests
//
//  Covers ``DiskCache`` round-tripping after the coder pair moved from per-operation
//  allocation to stored properties (#13). Reusing one decoder and encoder must not
//  change what is written or read, including across repeated and concurrent use.
//

@testable import BuddyAppKit
import Foundation
import os
import Testing

struct DiskCacheTests {
    /// `nonisolated`: the package defaults to main-actor isolation, so the Codable
    /// conformance would otherwise be main-actor-bound and unusable from the
    /// concurrent test below.
    private nonisolated struct Snapshot: Codable, Equatable {
        let id: Int
        let title: String
        let updatedAt: Date
    }

    /// A cache in its own directory so tests can't collide with each other.
    private func makeCache() -> DiskCache {
        DiskCache(directoryName: "BuddyAppKitTests/\(UUID().uuidString)",
                  logger: Logger(subsystem: "BuddyAppKitTests", category: "disk-cache"))
    }

    @Test func `a saved value round-trips`() {
        let cache = makeCache()
        let account = UUID()
        let value = Snapshot(id: 1, title: "Reverse a list", updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        cache.save(value, kind: "pads", account: account)
        #expect(cache.load(Snapshot.self, kind: "pads", account: account) == value)
    }

    @Test func `repeated use of the shared coders round-trips identically`() {
        // The regression #13 could introduce: a reused coder carrying state between
        // calls. Ten writes and reads must behave like ten fresh ones.
        let cache = makeCache()
        let account = UUID()
        for index in 0 ..< 10 {
            let value = Snapshot(id: index, title: "Q\(index)", updatedAt: Date(timeIntervalSince1970: Double(index)))
            cache.save(value, kind: "questions", account: account)
            #expect(cache.load(Snapshot.self, kind: "questions", account: account) == value)
        }
    }

    @Test func `separate accounts and kinds do not collide`() {
        let cache = makeCache()
        let first = UUID()
        let second = UUID()
        let a = Snapshot(id: 1, title: "first", updatedAt: Date(timeIntervalSince1970: 1))
        let b = Snapshot(id: 2, title: "second", updatedAt: Date(timeIntervalSince1970: 2))

        cache.save(a, kind: "pads", account: first)
        cache.save(b, kind: "pads", account: second)
        #expect(cache.load(Snapshot.self, kind: "pads", account: first) == a)
        #expect(cache.load(Snapshot.self, kind: "pads", account: second) == b)
        #expect(cache.load(Snapshot.self, kind: "questions", account: first) == nil)
    }

    @Test func `a missing entry loads as nil`() {
        #expect(makeCache().load(Snapshot.self, kind: "pads", account: UUID()) == nil)
    }

    @Test func `a deleted entry loads as nil`() {
        let cache = makeCache()
        let account = UUID()
        cache.save(Snapshot(id: 1, title: "x", updatedAt: Date()), kind: "pads", account: account)
        cache.delete(kind: "pads", account: account)
        #expect(cache.load(Snapshot.self, kind: "pads", account: account) == nil)
    }

    @Test func `a corrupt snapshot is removed after its first failed decode`() throws {
        let cache = makeCache()
        let account = UUID()
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appending(path: cache.directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "pads-\(account.uuidString).json")
        try Data("not-json".utf8).write(to: file)

        #expect(cache.load(Snapshot.self, kind: "pads", account: account) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(cache.load(Snapshot.self, kind: "pads", account: account) == nil)
    }

    @Test func `concurrent saves and loads across accounts round-trip`() async {
        // The coders are shared across calls now, and DiskCache is Sendable, so
        // concurrent use has to stay correct (#13).
        let cache = makeCache()
        let accounts = (0 ..< 8).map { _ in UUID() }
        await withTaskGroup(of: Bool.self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    let value = Snapshot(id: index,
                                         title: "concurrent \(index)",
                                         updatedAt: Date(timeIntervalSince1970: Double(index)))
                    cache.save(value, kind: "pads", account: account)
                    return cache.load(Snapshot.self, kind: "pads", account: account) == value
                }
            }
            for await roundTripped in group {
                #expect(roundTripped)
            }
        }
    }
}
