//
//  URLOpenerTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Foundation
import Testing

@MainActor
struct URLOpenerTests {
    @Test("platform URL-open failures are returned to the caller")
    func reportsPlatformFailure() async {
        let url = URL.staticURL("https://example.com")

        let failed = await URLOpener.open(url) { _ in false }
        let succeeded = await URLOpener.open(url) { _ in true }

        #expect(!failed)
        #expect(succeeded)
    }
}
