//
//  Glass.swift
//  BuddyDesignSystem
//
//  Generic Liquid Glass primitives extracted from the app (#377): the chip capsule
//  and label-colour helpers, which give the filter / saved-search chips interactive
//  Liquid Glass on macOS 26 with an opaque-material fallback on macOS 15. Domain-free,
//  so the HackerRank app can reuse them.
//
//  The floating-glass, glass button-style, and GlassCluster compatibility wrappers were
//  removed in #7 once every client moved to the OS 26 native APIs (glassEffect,
//  .buttonStyle(.glass) / .buttonStyle(.glassProminent), GlassEffectContainer). Only the
//  chip helpers remain, because buddy-kit still targets macOS 15 and its own chips
//  (FilterChipMenu, SavedSearchChip) still need the pre-26 fallback.
//

import SwiftUI

public extension View {
    /// Backs a filter chip with a capsule that reads as a distinct control. On
    /// macOS 26 the idle chip gets interactive Liquid Glass (and an accent-tinted
    /// glass when its filter is set), so a row of chips floats above the list as a
    /// clear functional layer rather than bare text + chevron (#352 — the owner
    /// wants these to plainly read as controls, and prioritises the Tahoe look).
    /// On macOS 15 it falls back to the opaque capsule fill + hairline stroke the
    /// chips have always used. The filter bar sits in the control layer above the
    /// list content, so glass here matches Apple's guidance even though dense
    /// *content*-layer surfaces (cards, list rows, badges) still keep flat material.
    ///
    /// `shape` defaults to a `Capsule` (the filter chips' pill); the saved-search
    /// chips pass a rounded rectangle so the two chip families read as visibly
    /// different controls — recall "tokens" versus filter "pills" (#405).
    @ViewBuilder
    func chipCapsule(
        glassTint: Color?,
        fallbackFill: some ShapeStyle,
        fallbackStroke: Color,
        fallbackStrokeWidth: CGFloat,
        in shape: some Shape = Capsule()
    ) -> some View {
        #if os(visionOS)
            background(fallbackFill, in: shape)
                .overlay(shape.stroke(fallbackStroke, lineWidth: fallbackStrokeWidth))
        #else
            if #available(macOS 26, iOS 26, tvOS 26, *) {
                let glass: Glass = (glassTint.map { Glass.regular.tint($0) } ?? .regular).interactive()
                glassEffect(glass, in: shape)
            } else {
                background(fallbackFill, in: shape)
                    .overlay(shape.stroke(fallbackStroke, lineWidth: fallbackStrokeWidth))
            }
        #endif
    }
}

/// The readable label colour for a filter chip given whether its filter is set.
/// An idle chip uses `.primary`. A *set* chip on macOS 26 wears accent-tinted
/// (saturated) glass via ``chipCapsule``, so its label must be white — the same
/// pairing the system uses for `.glassProminent` — because accent text on the
/// accent capsule is unreadable (#397). On macOS 15 the set chip instead wears a
/// light-accent fill, where the accent label reads fine, so it keeps the accent.
@MainActor
public func chipLabelColor(isActive: Bool) -> Color {
    guard isActive else { return .primary }

    #if !os(visionOS)
        if #available(macOS 26, iOS 26, tvOS 26, *) {
            return .white
        }
    #endif
    return .accentColor
}
