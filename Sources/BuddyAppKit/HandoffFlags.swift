//
//  HandoffFlags.swift
//  BuddyAppKit
//
//  The ~6 identical `NSUserActivity` Handoff eligibility lines both interview apps set
//  when advertising the item on screen (#645): Handoff, Spotlight search, Siri
//  prediction (iOS-only), and the `webpageURL` that drives the browser fallback and a
//  stable Spotlight identity. Only the FLAG-SETTING is shared here; the activity type,
//  title, and `userInfo` payload stay app-side.
//

import Foundation

public extension NSUserActivity {
    /// Marks this activity as eligible for Handoff and Spotlight search, sets its
    /// `webpageURL` (when provided) for the browser / Spotlight fallback, and — on iOS —
    /// makes it eligible for Siri prediction. Call from the app's `userActivity` update
    /// closure after setting the title and `userInfo`.
    ///
    /// `isEligibleForPrediction` is an iOS-only eligibility flag, so it is set only under
    /// `#if !os(macOS)`.
    ///
    /// `nonisolated` because the `NSUserActivity` eligibility flags aren't actor-isolated,
    /// so a `nonisolated` `userActivity` update path (e.g. a `nonisolated static configure`)
    /// can adopt the shared helper instead of inlining the flag lines.
    nonisolated func applyBuddyHandoffFlags(webpageURL: URL? = nil) {
        isEligibleForHandoff = true
        isEligibleForSearch = true
        if let webpageURL { self.webpageURL = webpageURL }
        #if os(iOS)
            isEligibleForPrediction = true
        #endif
    }
}
