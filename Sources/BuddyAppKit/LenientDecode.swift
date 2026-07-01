//
//  LenientDecode.swift
//  BuddyAppKit
//
//  A forgiving optional decode shared by the interview apps' decode-only models (#646).
//  Returns `nil` for a missing key, an explicit null, *or* a value of the wrong type,
//  instead of throwing — but logs the swallowed error so silent API drift shows up in
//  Console rather than producing an empty UI with no diagnostic. (The logging version
//  from PadBuddy, strictly better than a silent `try?`.)
//
//  Why it matters: a loader that decodes a `data` array leniently drops any element that
//  throws rather than failing the whole page. That backstop turns a single over-strict
//  field into silent data loss: a model field marked required but absent/null on some
//  live records makes every such record vanish. Models use this in `init(from:)` so one
//  odd field defaults instead of dropping the record.
//

import Foundation
import os.log

private nonisolated let lenientDecodeLogger = Logger(
    subsystem: "com.adamdangoor.buddyappkit", category: "decode"
)

public extension KeyedDecodingContainer {
    /// Like `try? decodeIfPresent`, but logs the underlying error so silent API drift is
    /// diagnosable. Missing key, explicit null, and a type mismatch all collapse to `nil`.
    ///
    /// `nonisolated` because models decode off the main actor inside a REST client, while
    /// `BuddyAppKit`'s default actor isolation is `MainActor`.
    nonisolated func lenientDecodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            lenientDecodeLogger.debug(
                """
                decodeIfPresent '\(key.stringValue, privacy: .public)' \
                as \(String(describing: type), privacy: .public) \
                failed: \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }
}
