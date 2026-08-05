//
//  ClipboardTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Testing

@MainActor
struct ClipboardTests {
    @Test("sensitive-copy limits count UTF-8 bytes")
    func sensitiveCopyLimitUsesUTF8Bytes() {
        #expect(Clipboard.sensitiveTextFits("token", maximumUTF8Bytes: 5))
        #expect(!Clipboard.sensitiveTextFits("token", maximumUTF8Bytes: 4))
        #expect(Clipboard.sensitiveTextFits("🔑", maximumUTF8Bytes: 4))
        #expect(!Clipboard.sensitiveTextFits("🔑", maximumUTF8Bytes: 3))
        #expect(!Clipboard.sensitiveTextFits("", maximumUTF8Bytes: -1))
    }

    @Test("sensitive-copy expiry clears only the unchanged pasteboard")
    func expiryRespectsLaterCopies() async {
        var cleared = false
        await Clipboard.expireSensitiveCopy(
            copiedChangeCount: 7,
            sleep: {},
            currentChangeCount: { 7 },
            clear: { cleared = true }
        )
        #expect(cleared)

        cleared = false
        await Clipboard.expireSensitiveCopy(
            copiedChangeCount: 7,
            sleep: {},
            currentChangeCount: { 8 },
            clear: { cleared = true }
        )
        #expect(!cleared)
    }

    @Test("cancelled expiry work leaves the pasteboard untouched")
    func cancelledExpiryDoesNotClear() async {
        var cleared = false
        await Clipboard.expireSensitiveCopy(
            copiedChangeCount: 7,
            sleep: { throw CancellationError() },
            currentChangeCount: { 7 },
            clear: { cleared = true }
        )
        #expect(!cleared)
    }
}
