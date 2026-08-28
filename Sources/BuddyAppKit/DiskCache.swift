//
//  DiskCache.swift
//  BuddyAppKit
//
//  On-disk JSON backing for per-account list caches, with the cache directory and
//  logger injected so each app picks its own location (#512). Lifted from the
//  coderpad app. Snapshots live in Application Support, one JSON file per account +
//  kind; the encoder/decoder pair is symmetric (default strategies), so it
//  round-trips the API models faithfully without depending on the API's date format.
//

import Foundation
import os

public nonisolated struct DiskCache: Sendable {
    /// The Application-Support-relative directory snapshots live under (e.g.
    /// "com.example.app/DataCache"). Injected so each app keeps its own location.
    public let directoryName: String
    /// Maximum bytes read from one snapshot. The reader consumes at most this value
    /// plus one byte, so oversized files are rejected without being materialized.
    public let maximumSnapshotBytes: Int
    private let logger: Logger
    /// One coder pair per cache, not one per operation.
    ///
    /// These were built inside `load` and `save`, so a consumer reading and writing
    /// per account and per kind allocated a fresh coder every time — including on the
    /// cold-launch path, where snapshots for every account are merged before first
    /// paint (#13). Foundation coders retain mutable state, so every access is guarded
    /// by `operationLock`; the pair is never entered concurrently.
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    /// Keeps reads, writes, deletes, and corrupt-file cleanup on this cache instance
    /// atomic relative to one another, so cleanup can never remove a newer save.
    private let operationLock = NSLock()
    /// Coordinates the same snapshot across separately constructed cache instances.
    private static let pathLocks = DiskCachePathLocks()
    /// Application Support is looked up and the cache directory created once per
    /// process per `directoryName`, not per operation.
    ///
    /// `url(kind:account:)` runs on every load, save, delete, and `modificationDate`,
    /// and a consumer's read path can call it twice — once for a freshness check and
    /// once for the load. So a `FileManager.urls(for:in:)` lookup and a
    /// `createDirectory` ran on every cache access, on paths the app hits for each
    /// list render fallback, prewarm, freshness probe, and background refresh (#4766).
    private static let directories = DiskCacheDirectories()

    public init(directoryName: String, logger: Logger, maximumSnapshotBytes: Int = 10_000_000) {
        self.directoryName = directoryName
        self.logger = logger
        self.maximumSnapshotBytes = max(0, maximumSnapshotBytes)
    }

    private func url(kind: String, account: UUID) -> URL? {
        guard let resolved = Self.directories.resolve(relativePath: directoryName) else {
            logger.error("Rejecting unsafe DiskCache path")
            return nil
        }
        guard let snapshot = DiskCachePathPolicy.snapshotURL(
            directory: resolved.directory, root: resolved.root, kind: kind, account: account
        ) else {
            logger.error("Rejecting unsafe DiskCache path")
            return nil
        }
        return snapshot
    }

    public func load<T: Decodable>(_: T.Type, kind: String, account: UUID) -> T? {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account) else { return nil }
        return Self.pathLocks.withLock(for: url) {
            guard let data = readSnapshot(at: url, kind: kind) else { return nil }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                let reason = error.localizedDescription
                logger.error("Failed to decode \(kind, privacy: .public) cache: \(reason, privacy: .public)")
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    let removalReason = error.localizedDescription
                    logger.error(
                        "Failed to remove corrupt \(kind, privacy: .public) cache: \(removalReason, privacy: .public)"
                    )
                }
                return nil
            }
        }
    }

    private func readSnapshot(at url: URL, kind: String) -> Data? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let readCeiling = maximumSnapshotBytes == Int.max
                ? Int.max
                : maximumSnapshotBytes + 1
            var data = Data()

            while data.count < readCeiling {
                let bytesToRead = min(64 * 1024, readCeiling - data.count)
                guard let chunk = try handle.read(upToCount: bytesToRead),
                      !chunk.isEmpty else { return data }
                data.append(chunk)
            }

            guard data.count <= maximumSnapshotBytes else {
                logger.error(
                    "Ignoring oversized \(kind, privacy: .public) cache: limit is \(self.maximumSnapshotBytes) bytes"
                )
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    public func save(_ value: some Encodable, kind: String, account: UUID) {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account) else { return }

        Self.pathLocks.withLock(for: url) {
            let data: Data
            do {
                data = try encoder.encode(value)
            } catch {
                let reason = error.localizedDescription
                logger.error("Failed to encode \(kind, privacy: .public) cache: \(reason, privacy: .public)")
                return
            }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                // The directory is created once per process, so one removed out from
                // under us would otherwise fail every later save. Recreate and retry
                // once before reporting (#4766).
                Self.directories.recreate(relativePath: directoryName)
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    let reason = error.localizedDescription
                    logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
                }
            }
        }
    }

    public func delete(kind: String, account: UUID) {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account) else { return }

        Self.pathLocks.withLock(for: url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// When the snapshot for `kind`+`account` was last written, or nil if there's no file.
    /// Lets a reader (e.g. the headless MCP server, #520) judge freshness without loading
    /// and decoding the whole snapshot.
    public func modificationDate(kind: String, account: UUID) -> Date? {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account) else { return nil }
        return Self.pathLocks.withLock(for: url) {
            guard let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path
            ) else { return nil }
            return attributes[.modificationDate] as? Date
        }
    }
}

/// Memoizes each cache directory's resolution and creation for the process.
private nonisolated final class DiskCacheDirectories: @unchecked Sendable {
    struct Resolved {
        let root: URL
        let directory: URL
    }

    private let lock = NSLock()
    private var resolved: [String: Resolved] = [:]

    func resolve(relativePath: String) -> Resolved? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = resolved[relativePath] { return cached }

        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let directory = DiskCachePathPolicy.directoryURL(root: root, relativePath: relativePath)
        else { return nil }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Resolved(root: root, directory: directory)
        resolved[relativePath] = entry
        return entry
    }

    /// Re-creates a memoized directory that has since been removed.
    func recreate(relativePath: String) {
        lock.lock()
        let directory = resolved[relativePath]?.directory
        lock.unlock()
        guard let directory else { return }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// One process-wide lock per snapshot path, ordering operations on the same file
/// across separately constructed `DiskCache` values.
///
/// This was a fixed pool of 64 locks indexed by the path's `hashValue`, so two
/// unrelated snapshots collided into one lock roughly 1 in 64 times and serialized
/// against each other for no reason — and because `String.hashValue` is seeded per
/// process, which pairs collided changed from run to run. Locks are created on
/// demand and dropped when their last holder leaves, so the table stays as small as
/// the work in flight rather than retaining a key per snapshot ever touched.
private nonisolated final class DiskCachePathLocks: @unchecked Sendable {
    private struct Entry {
        let lock: NSLock
        var users: Int
    }

    private let tableLock = NSLock()
    private var entries: [String: Entry] = [:]

    func withLock<Result>(for url: URL, _ operation: () throws -> Result) rethrows -> Result {
        let key = url.standardizedFileURL.path
        let lock = retainLock(for: key)
        lock.lock()
        defer {
            lock.unlock()
            releaseLock(for: key)
        }
        return try operation()
    }

    private func retainLock(for key: String) -> NSLock {
        tableLock.lock()
        defer { tableLock.unlock() }

        var entry = entries[key] ?? Entry(lock: NSLock(), users: 0)
        entry.users += 1
        entries[key] = entry
        return entry.lock
    }

    private func releaseLock(for key: String) {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard var entry = entries[key] else { return }

        entry.users -= 1
        entries[key] = entry.users > 0 ? entry : nil
    }
}

nonisolated enum DiskCachePathPolicy {
    static func directoryURL(root: URL, relativePath: String) -> URL? {
        guard !relativePath.hasPrefix("/") else { return nil }
        let components = relativePath.split(
            separator: "/", omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty, components.allSatisfy(isValidComponent) else { return nil }

        let directory = components.reduce(root) { partial, component in
            partial.appending(path: component, directoryHint: .isDirectory)
        }.standardizedFileURL
        return isStrictDescendant(directory, of: root) ? directory : nil
    }

    static func snapshotURL(directory: URL, root: URL, kind: String, account: UUID) -> URL? {
        guard isValidComponent(kind) else { return nil }
        let snapshot = directory
            .appending(path: "\(kind)-\(account.uuidString).json")
            .standardizedFileURL
        return isStrictDescendant(snapshot, of: root) ? snapshot : nil
    }

    private static func isValidComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\\")
            && !component.contains("\0")
    }

    private static func isStrictDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath.hasPrefix(rootPath + "/")
    }
}
