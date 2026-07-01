//
//  JSONLLog.swift
//  BuddyMCP
//
//  A tiny append-only JSONL store, lifted from the identical activity-log files both
//  host apps kept for their in-app MCP server (#647, #523/#52). The headless `--mcp`
//  process is a separate launch from the running GUI, so it records what it does to a
//  small file in the shared app-support container; the settings pane tails that file.
//
//  Both apps wrote byte-identical machinery around it - a `FileHandle`/`seekToEnd`
//  append (creating the file on the first write), a tolerant line-by-line parse that
//  skips a torn or malformed line rather than failing the whole read, a `maxEntries` cap,
//  and a `clear()` that removes the file. Only the entry schema and the cap differed, so
//  those are the generic parameters here; each app keeps its own `Entry` type.
//
//  Concurrency: several MCP clients can each launch their own `--mcp` process, so writes
//  are append-only (small atomic appends). Trimming to the last N entries is done by the
//  GUI (a single reader) when it loads, avoiding multi-process rewrite races. Every member
//  is nonisolated, so the headless server can append from any context.
//

import Foundation

/// An append-only JSONL log of `Entry` values, shared by a GUI reader and one or more
/// headless writer processes via a file in a directory both can reach.
///
/// The store owns only its file location and cap; the caller decides where entries come
/// from and how they're shown. `Entry` is `Codable & Sendable` so the log crosses process
/// and isolation boundaries safely.
public struct JSONLLog<Entry: Codable & Sendable>: Sendable {
    /// The directory holding the log file. Created on demand when appending.
    public let directory: URL

    /// The log file's name within `directory`, e.g. `"mcp-activity.jsonl"`.
    public let fileName: String

    /// The most recent entries kept; older ones are dropped when the GUI calls `trim()`,
    /// and reads return at most this many.
    public let maxEntries: Int

    private let encode: @Sendable (Entry) -> Data?
    private let decode: @Sendable (Data) -> Entry?

    /// Creates a log at `directory/fileName`, keeping at most `maxEntries`.
    ///
    /// Dates are encoded and decoded as ISO-8601 by default (matching both apps'
    /// activity logs); pass custom `encoder`/`decoder` to change that.
    public init(
        directory: URL,
        fileName: String,
        maxEntries: Int,
        encoder: JSONEncoder = JSONLLog.iso8601Encoder,
        decoder: JSONDecoder = JSONLLog.iso8601Decoder
    ) {
        self.directory = directory
        self.fileName = fileName
        self.maxEntries = maxEntries
        // Capture the coders behind Sendable closures so the struct stays Sendable
        // (JSONEncoder/JSONDecoder are reference types).
        encode = { try? encoder.encode($0) }
        decode = { try? decoder.decode(Entry.self, from: $0) }
    }

    /// A JSON encoder writing dates as ISO-8601 - the default for a `JSONLLog`.
    public static var iso8601Encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// A JSON decoder reading ISO-8601 dates - the default for a `JSONLLog`.
    public static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The full path to the log file, creating `directory` if needed. Returns nil only
    /// when the directory can't be created.
    private var fileURL: URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }

        return directory.appending(path: fileName)
    }

    /// Appends `entry` as one JSON line. Uses an open handle seeked to the end when the
    /// file already exists, else creates it with this first line. A non-encodable entry is
    /// silently dropped.
    public func append(_ entry: Entry) {
        guard let url = fileURL,
              let data = encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let payload = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            // First write: create the file with this line.
            try? payload.write(to: url, options: .atomic)
        }
    }

    /// The stored entries, oldest first, capped to the last `maxEntries`. Decodes
    /// tolerantly: a malformed line (e.g. a torn concurrent append) is skipped rather than
    /// failing the whole read. An absent file reads as empty.
    public func load() -> [Entry] {
        guard let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let entries = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> Entry? in
                guard let data = line.data(using: .utf8) else { return nil }

                return decode(data)
            }
        return Array(entries.suffix(maxEntries))
    }

    /// Rewrites the file to only its last `maxEntries` lines when it has grown past the
    /// cap, so the log can't grow without bound. Call from the single GUI reader after a
    /// load, so it doesn't race the headless appenders. A no-op when already within the cap.
    public func trim() {
        guard let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxEntries else { return }

        let trimmed = lines.suffix(maxEntries).joined(separator: "\n") + "\n"
        try? Data(trimmed.utf8).write(to: url, options: .atomic)
    }

    /// Deletes the log file, e.g. so it doesn't outlive the data it describes.
    public func clear() {
        guard let url = fileURL else { return }

        try? FileManager.default.removeItem(at: url)
    }
}
