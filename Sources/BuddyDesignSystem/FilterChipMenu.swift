//
//  FilterChipMenu.swift
//  BuddyDesignSystem
//
//  The generic, domain-free filter-chip primitives shared by both apps: the
//  focus-ring suppressor, the menu-backed chip shell, and the categorical
//  `FilterChipMenu`. Lifted out of the app (#515) so the chip vocabulary lives
//  beside the other design-system components. Domain-specific chips (date-range,
//  saved-search) stay app-side and build on the public `ChipMenuShell`.
//

import SwiftUI

/// Shared shell for the menu-backed filter chips. Draws one capsule around a
/// `Menu` and — when a filter is set — a sibling clear (×) button. The × is a real
/// sibling laid out *beside* the menu rather than overlaid on top of it: a SwiftUI
/// `Button` placed over a `Menu` lets the click leak into the menu's synchronous
/// AppKit tracking loop, which beach-balls on clear. Keeping them side by side
/// means a click on the × never reaches the menu.
public struct ChipMenuShell<MenuContent: View>: View {
    let icon: String
    let text: String
    let isActive: Bool
    let fillColor: Color
    let strokeColor: Color
    let labelColor: Color
    var menuDisabled: Bool
    let clearLabel: String
    let accessibilityTitle: String?
    let accessibilityValue: String?
    let onClear: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        icon: String,
        text: String,
        isActive: Bool,
        fillColor: Color,
        strokeColor: Color,
        labelColor: Color,
        menuDisabled: Bool,
        clearLabel: String,
        accessibilityTitle: String? = nil,
        accessibilityValue: String? = nil,
        onClear: @escaping () -> Void,
        @ViewBuilder menu: @escaping () -> MenuContent,
    ) {
        self.icon = icon
        self.text = text
        self.isActive = isActive
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.labelColor = labelColor
        self.menuDisabled = menuDisabled
        self.clearLabel = clearLabel
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityValue = accessibilityValue
        self.onClear = onClear
        self.menu = menu
    }

    public var body: some View {
        HStack(spacing: 4) {
            Menu {
                menu()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.caption).accessibilityHidden(true)
                    Text(text).font(.callout).lineLimit(1)
                    // Drop the disclosure chevron when active — the × takes the
                    // trailing slot — so the chip doesn't grow a second glyph.
                    if !isActive {
                        Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(accessibilityTitle ?? text)
            .accessibilityValue(accessibilityValue ?? text)
            .touchTarget()
            .disabled(menuDisabled)

            if isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .touchTarget()
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(labelColor)
        .chipCapsule(
            glassTint: isActive ? .accentColor : nil,
            fallbackFill: fillColor,
            fallbackStroke: strokeColor,
            fallbackStrokeWidth: ChipContrast.lineWidth(contrast),
        )
        .fixedSize()
    }
}

// A categorical filter chip: a labelled menu of mutually exclusive options bound to
// an optional selection, with a checkmark on the current choice and a reset row.

/// Localized once for the whole process rather than per construction.
///
/// `FilterChipMenu` is generic, which cannot hold a static stored property, so this
/// lives beside it. As a default argument the lookup was evaluated at every call site
/// that omitted it, and these chips are built inside a parent's `body` — so it ran on
/// every render of the filter bar (#12).
public enum FilterChipDefaults {
    public static let resetLabel = String(localized: "All")
}

public struct FilterChipMenu<Option: Hashable>: View {
    let title: String
    let icon: String
    @Binding var selected: Option?
    let options: [Option]
    let formatter: (Option) -> String
    /// The label of the row that clears the filter. "All" reads naturally for the
    /// categorical chips (State, Language, …); callers can override it.
    var resetLabel: String
    /// Built in `init`, not in `body`: it only depends on `title`, and evaluating it
    /// per render meant a String Catalog lookup plus an interpolation for every chip
    /// on every pass of a filter bar that rebuilds on each keystroke (#12).
    let clearLabel: String

    public init(
        title: String,
        icon: String,
        selected: Binding<Option?>,
        options: [Option],
        formatter: @escaping (Option) -> String,
        resetLabel: String = FilterChipDefaults.resetLabel,
    ) {
        self.title = title
        self.icon = icon
        _selected = selected
        self.options = options
        self.formatter = formatter
        self.resetLabel = resetLabel
        clearLabel = String(localized: "Clear \(title) filter")
    }

    /// Match SearchableFilterChip's selected/idle styling so a set filter always
    /// shows the accent capsule. Idle wears the neutral chip pill so it reads as a
    /// control (#352); a selection paints the same accent fill, stroke, and text
    /// colour the Owner chip uses.
    private var isActive: Bool {
        selected != nil
    }

    private var fillColor: Color {
        isActive ? Color.accentColor.opacity(0.18) : Color.chipIdleFill
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.4) : Color.subtleStroke
    }

    private var labelColor: Color {
        chipLabelColor(isActive: isActive)
    }

    public var body: some View {
        ChipMenuShell(
            icon: icon,
            text: selected.map(formatter) ?? title,
            isActive: isActive,
            fillColor: fillColor,
            strokeColor: strokeColor,
            labelColor: labelColor,
            menuDisabled: options.isEmpty,
            clearLabel: clearLabel,
            accessibilityTitle: title,
            accessibilityValue: selected.map(formatter) ?? resetLabel,
            onClear: { selected = nil },
            menu: {
                Picker(title, selection: $selected) {
                    Text(resetLabel).tag(Option?.none)
                    ForEach(options, id: \.self) { option in
                        Text(formatter(option)).tag(Optional(option))
                    }
                }
                .pickerStyle(.inline)
            },
        )
    }
}
