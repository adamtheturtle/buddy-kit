//
//  PopoverSelectionRow.swift
//  BuddyDesignSystem
//
//  A single selectable row for a searchable picker popover, lifted from the coderpad
//  filter chips. A leading checkmark/circle marks selection, a label names the option,
//  and an optional monospaced trailing subtitle carries a secondary value (an id, a
//  count). Hover-highlighted, plain-button. Domain-neutral: the caller supplies all
//  copy and the selection/action, so any app's option picker can compose these rows.
//

import SwiftUI

/// A checkmark/label/subtitle selection row for a picker popover. Zero-config reproduces
/// the standard look: an accent checkmark when selected (a dim circle otherwise), the
/// label, and an optional monospaced caption subtitle, with an accent hover fill.
public struct PopoverSelectionRow: View {
    private let label: String
    private let subtitle: String?
    private let isSelected: Bool
    private let action: () -> Void

    @State private var hovered = false

    public init(
        label: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                    .frame(width: 16)
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(hovered ? Color.accentColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
