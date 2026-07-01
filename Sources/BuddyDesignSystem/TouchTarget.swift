//
//  TouchTarget.swift
//  BuddyDesignSystem
//
//  Platform-gated touch-affordance helpers, lifted from the coderpad app so the
//  shared controls (saved-search chips, inline editors) carry their own iPad touch
//  ergonomics. Many controls are shared with the macOS layout, where they were tuned
//  for a mouse pointer (icon-only, .plain/.borderless, caption glyphs, no padding)
//  and are fiddly to hit on iPad touch. Both helpers are no-ops on macOS so the
//  compact pointer layout stays byte-identical.
//

import SwiftUI

public extension View {
    /// Guarantees at least a `side` x `side` hit target on touch platforms (Apple's
    /// 44pt HIG minimum, #597), expanding the tappable frame around the (unchanged)
    /// content and making the whole frame hittable. A no-op on macOS, where the
    /// pointer-tuned resting layout should stay compact and unchanged.
    func touchTarget(_ side: CGFloat = 44) -> some View {
        #if os(macOS)
            self
        #else
            frame(minWidth: side, minHeight: side).contentShape(Rectangle())
        #endif
    }

    /// Applies the standard iPadOS pointer hover effect so a trackpad/Magic Keyboard
    /// pointer highlights this control as it moves over it (#586). A no-op on macOS,
    /// where hover is handled by the existing `onHover` opacity treatment on rows.
    func pointerHoverEffect() -> some View {
        #if os(macOS)
            self
        #else
            hoverEffect()
        #endif
    }
}
