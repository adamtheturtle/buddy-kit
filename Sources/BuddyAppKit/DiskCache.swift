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

    public init(directoryName: String, logger: Logger) {
        self.directoryName = directoryName
        self.logger = logger
    }

    private func url(kind: String, account: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }

        let dir = base.appending(path: directoryName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(kind)-\(account.uuidString).json")
    }

    public func load<T: Decodable>(_: T.Type, kind: String, account: UUID) -> T? {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account),
              let data = try? Data(contentsOf: url) else { return nil }

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

    public func save(_ value: some Encodable, kind: String, account: UUID) {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account) else { return }

        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
        }
    }

    public func delete(kind: String, account: UUID) {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account) else { return }

        try? FileManager.default.removeItem(at: url)
    }

    /// When the snapshot for `kind`+`account` was last written, or nil if there's no file.
    /// Lets a reader (e.g. the headless MCP server, #520) judge freshness without loading
    /// and decoding the whole snapshot.
    public func modificationDate(kind: String, account: UUID) -> Date? {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard let url = url(kind: kind, account: account),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }

        return attributes[.modificationDate] as? Date
    }
}
