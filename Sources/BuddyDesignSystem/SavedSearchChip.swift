//
//  SavedSearchChip.swift
//  BuddyDesignSystem
//
//  The saved-search recall token shown in a filter bar, lifted from the coderpad
//  app (#649). Nearly identical between the two apps, so it lives here and both
//  compose it. Tapping a chip *applies* a saved set of filters rather than toggling
//  a value, so it stays neutral until applied — at which point it wears the same
//  accent the active filter chips use. Deliberately a rounded *rectangle* rather
//  than the filter chips' `Capsule`, so recall tokens and filter pills read as
//  distinct families even when both glow accent while applied (#405).
//

import SwiftUI

/// A saved-search recall chip: an icon, the search name, and — unless it's a
/// built-in default — a trailing delete glyph. Neutral until `isActive`, when it
/// paints the accent capsule (matching the active filter chips) to mark "you are
/// here". Uses the ``chipCapsule`` primitive so it gets Liquid Glass on macOS 26 /
/// iOS 26 with the opaque fill + hairline fallback on macOS 15.
public struct SavedSearchChip: View {
    private let name: String
    private let systemImage: String
    private let isActive: Bool
    private let maxNameLength: Int
    private let onApply: () -> Void
    private let onDelete: (() -> Void)?

    @State private var hovered = false

    /// - Parameters:
    ///   - name: The saved search's name, shown on the chip (clamped for display).
    ///   - systemImage: The leading SF Symbol; defaults to a filled bookmark.
    ///   - isActive: True while the list's live filters exactly match this search —
    ///     derived by the parent from filter state rather than stored, so it can
    ///     never drift out of sync with what's shown.
    ///   - maxNameLength: The character count past which the displayed name is
    ///     clamped with a trailing ellipsis (the full name stays in the a11y label).
    ///     Values below one are treated as one. Defaults to 40, the limit new names
    ///     are capped to on save.
    ///   - onApply: Applies this search's filters (the chip's primary tap action).
    ///   - onDelete: Deletes the saved search. Omit (`nil`) for built-in defaults,
    ///     which can't be deleted — then no delete glyph is shown.
    public init(
        name: String,
        systemImage: String = "bookmark.fill",
        isActive: Bool = false,
        maxNameLength: Int = 40,
        onApply: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.name = name
        self.systemImage = systemImage
        self.isActive = isActive
        self.maxNameLength = max(1, maxNameLength)
        self.onApply = onApply
        self.onDelete = onDelete
    }

    /// The token shape for saved-search chips: a rounded rectangle, deliberately
    /// distinct from the filter chips' `Capsule`, so the recall tokens and the
    /// filter pills are told apart at a glance regardless of accent state (#405).
    /// Uses the shared `Radius.chip` token rather than a hard-coded radius.
    static let tokenShape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)

    /// Saved searches are *recall* buttons, not state: tapping one launches a set
    /// of filters rather than toggling a value. They stay neutral until applied, at
    /// which point the accent capsule marks "you are here" — the same accent the
    /// active filter chips use — until a filter is modified.
    private var fillStyle: AnyShapeStyle {
        if isActive { return AnyShapeStyle(Color.accentColor.opacity(0.16)) }
        return hovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }

    /// White on the accent glass capsule (macOS 26), accent on the light fallback
    /// fill (macOS 15) while applied, primary when idle — so an applied chip's text
    /// and icon stay readable instead of accent-on-accent (#397).
    private var contentColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(chipLabelColor(isActive: true)) : AnyShapeStyle(.primary)
    }

    /// The leading icon and the delete glyph: white on the accent glass capsule
    /// (macOS 26) / accent on the light fallback fill (macOS 15) while applied, and
    /// secondary when idle, so neither washes out against the applied chip (#397).
    private var iconColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(chipLabelColor(isActive: true)) : AnyShapeStyle(.secondary)
    }

    /// New names are capped on save, but names persisted before the cap (or any
    /// odd multi-line paste) could still be unbounded. Clamp to `maxNameLength`
    /// with a trailing ellipsis so no single chip overflows the bar; the full name
    /// stays in the accessibility label below.
    private var displayName: String {
        guard name.count > maxNameLength else { return name }

        return String(name.prefix(maxNameLength - 1)) + "…"
    }

    public var body: some View {
        // `.isButton` is added below via a ternary that this rule's matcher doesn't
        // detect; the chip is correctly exposed as a button to VoiceOver.
        // swiftlint:disable:next accessibility_trait_for_button
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .accessibilityHidden(true)
                .foregroundStyle(iconColor)
            Text(displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(contentColor)
                .lineLimit(1)
            if let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(iconColor)
                }
                .buttonStyle(.borderless)
                // The ~11pt × glyph is a sub-20pt target; give it the 44pt touch floor
                // (no-op on macOS, #597) and a pointer hover highlight on iPad (#586).
                .touchTarget()
                .pointerHoverEffect()
                .accessibilityLabel("Delete saved search \(name)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        // Glass on macOS 26 (accent-tinted while applied; the interactive variant
        // supplies the hover/press response the manual fill gives on 15), opaque
        // shape on 15 (#352). A rounded *rectangle* rather than the filter chips'
        // capsule, so saved-search recall tokens read as a distinct family from the
        // filter pills even when both glow accent while applied (#405).
        .chipCapsule(
            glassTint: isActive ? .accentColor : nil,
            fallbackFill: fillStyle,
            fallbackStroke: strokeColor,
            fallbackStrokeWidth: 0.5,
            in: Self.tokenShape
        )
        .contentShape(Self.tokenShape)
        .onTapGesture { onApply() }
        #if !os(tvOS)
            .onHover { hovered = $0 }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Apply saved search \(name)")
    }
}
