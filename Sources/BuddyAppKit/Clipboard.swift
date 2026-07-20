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
}
