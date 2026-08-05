//
//  Clipboard.swift
//  BuddyAppKit
//
//  A thin seam over the system pasteboard so plain-text clipboard writes go through
//  one place instead of scattering `NSPasteboard` across the views. Keeping this
//  incidental AppKit API behind a single helper is a step toward multi-platform
//  portability (#287): a future iOS/iPadOS build can swap the body for `UIPasteboard`
//  without touching any call site.
//

import Foundation

#if os(macOS)
    import AppKit
#elseif !os(tvOS)
    import UIKit
#endif

public enum Clipboard {
    /// Default ceiling for secrets such as tokens and generated configuration.
    public static let sensitiveCopyByteLimit = 64 * 1024

    /// Replace the pasteboard contents with `text` as a plain string.
    public static func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #elseif !os(tvOS)
            UIPasteboard.general.string = text
        #endif
    }

    /// Replace the pasteboard with `text` plus an optional rich-text (RTF)
    /// representation, so pasting into Pages, Mail, or a doc keeps formatting (e.g.
    /// syntax colours) while plain `.string` stays the fallback for editors and the
    /// terminal. Keeps the `.rtf` pasteboard type behind the seam alongside the
    /// plain-text write.
    public static func copy(_ text: String, rtf: Data?) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if let rtf { NSPasteboard.general.setData(rtf, forType: .rtf) }
        #elseif !os(tvOS)
            // UIPasteboard has no plain RTF type as a first-class slot; write the
            // plain string (the macOS RTF fallback isn't available on iOS).
            UIPasteboard.general.string = text
        #endif
    }

    /// Copies bounded sensitive text and removes it after `expiresAfter` while the
    /// process remains alive. The delayed clear is conditional on the pasteboard's
    /// change count, so it never erases something the user copied afterward.
    ///
    /// - Returns: `false` without changing the pasteboard when the UTF-8 payload
    ///   exceeds `maximumUTF8Bytes` or the platform has no writable pasteboard.
    @discardableResult
    public static func copySensitive(
        _ text: String,
        maximumUTF8Bytes: Int = sensitiveCopyByteLimit,
        expiresAfter: Duration = .seconds(60)
    ) -> Bool {
        guard sensitiveTextFits(text, maximumUTF8Bytes: maximumUTF8Bytes) else { return false }
        guard let copiedChangeCount = replacePlainText(text) else { return false }

        Task { @MainActor in
            await expireSensitiveCopy(
                copiedChangeCount: copiedChangeCount,
                sleep: {
                    guard expiresAfter > .zero else { return }
                    try await Task.sleep(for: expiresAfter)
                },
                currentChangeCount: pasteboardChangeCount,
                clear: clearPasteboard
            )
        }
        return true
    }

    static func sensitiveTextFits(_ text: String, maximumUTF8Bytes: Int) -> Bool {
        maximumUTF8Bytes >= 0 && text.utf8.count <= maximumUTF8Bytes
    }

    static func expireSensitiveCopy(
        copiedChangeCount: Int,
        sleep: () async throws -> Void,
        currentChangeCount: () -> Int?,
        clear: () -> Void
    ) async {
        do {
            try await sleep()
        } catch {
            return
        }
        guard currentChangeCount() == copiedChangeCount else { return }

        clear()
    }

    private static func replacePlainText(_ text: String) -> Int? {
        #if os(macOS)
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else { return nil }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { return nil }
            return pasteboard.changeCount
        #elseif !os(tvOS)
            UIPasteboard.general.string = text
            return UIPasteboard.general.changeCount
        #else
            return nil
        #endif
    }

    private static func pasteboardChangeCount() -> Int? {
        #if os(macOS)
            NSPasteboard.general.changeCount
        #elseif !os(tvOS)
            UIPasteboard.general.changeCount
        #else
            nil
        #endif
    }

    private static func clearPasteboard() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
        #elseif !os(tvOS)
            UIPasteboard.general.items = []
        #endif
    }
}
