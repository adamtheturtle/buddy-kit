//
//  AppearancePicker.swift
//  BuddyDesignSystem
//
//  The Light / Dark / System appearance picker, lifted from the coderpad app (#638)
//  and shared with the HackerRank app, whose copy had visually diverged. A row of
//  preview tiles the user clicks — mirroring macOS System Settings — rather than a
//  plain segmented control. Each tile renders a swatch in its own appearance (System
//  shows a diagonal light/dark split), with a selection ring and a labelled radio
//  beneath it.
//
//  Storage-agnostic: it binds a plain `ColorScheme?` (`nil` = follow the system) so
//  each app keeps its own `@AppStorage`/`AppAppearance` wiring and simply maps to and
//  from the optional scheme.
//

import SwiftUI

/// A three-way Light / Dark / System appearance picker bound to an optional
/// `ColorScheme` — `nil` follows the system. Feed the binding's value straight into
/// `.preferredColorScheme(_:)` on the app's window root.
public struct AppearancePicker: View {
    @Binding private var selection: ColorScheme?

    private let systemLabel: LocalizedStringKey
    private let lightLabel: LocalizedStringKey
    private let darkLabel: LocalizedStringKey

    /// - Parameters:
    ///   - selection: The forced color scheme, or `nil` to follow the system.
    ///   - systemLabel: The label under the "follow the system" tile. Defaults to
    ///     "System"; pass an app-specific `LocalizedStringKey` if the catalog keys it
    ///     differently.
    ///   - lightLabel: The label under the Light tile. Defaults to "Light".
    ///   - darkLabel: The label under the Dark tile. Defaults to "Dark".
    public init(
        selection: Binding<ColorScheme?>,
        systemLabel: LocalizedStringKey = "System",
        lightLabel: LocalizedStringKey = "Light",
        darkLabel: LocalizedStringKey = "Dark"
    ) {
        _selection = selection
        self.systemLabel = systemLabel
        self.lightLabel = lightLabel
        self.darkLabel = darkLabel
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(AppearanceOption.allCases) { option in
                tile(option)
            }
        }
    }

    private func label(for option: AppearanceOption) -> LocalizedStringKey {
        switch option {
        case .system: systemLabel
        case .light: lightLabel
        case .dark: darkLabel
        }
    }

    private func tile(_ option: AppearanceOption) -> some View {
        let isSelected = selection == option.colorScheme
        // The whole tile — swatch *and* the radio/label beneath it — is one button,
        // so clicking the circle under the picture selects the option too.
        return Button {
            selection = option.colorScheme
        } label: {
            VStack(spacing: 6) {
                AppearanceSwatch(option: option)
                    .frame(width: 104, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.subtleStroke,
                                    lineWidth: isSelected ? 3 : 1)
                    )
                Label {
                    Text(label(for: option)).font(.callout)
                } icon: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .font(.callout)
            }
            // Keep the whole tile area hit-testable, including the gap between
            // the swatch and the label.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = option.colorScheme }
    }
}

/// The three appearance choices the picker iterates over. Kept internal — callers
/// bind a plain `ColorScheme?` and never name these cases — so each app keeps its own
/// storage enum (e.g. `AppAppearance`) and only maps to/from the optional scheme.
enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// The color scheme this option forces, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The preview swatch inside an ``AppearancePicker`` tile: a small mock desktop and
/// window rendered in the given appearance, so the choice is recognizable at a
/// glance. System shows a diagonal light/dark split.
private struct AppearanceSwatch: View {
    let option: AppearanceOption

    var body: some View {
        ZStack {
            background
            // A small mock window to read as a desktop rather than a flat colour.
            RoundedRectangle(cornerRadius: Radius.tight, style: .continuous)
                .fill(windowFill)
                .overlay(RoundedRectangle(cornerRadius: Radius.tight, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: 60, height: 36)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 4, height: 4)
                        }
                    }
                    .padding(6)
                }
        }
    }

    @ViewBuilder private var background: some View {
        switch option {
        case .light: Color(white: 0.90)
        case .dark: Color(white: 0.16)
        case .system:
            LinearGradient(
                stops: [.init(color: Color(white: 0.90), location: 0.5),
                        .init(color: Color(white: 0.16), location: 0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var windowFill: Color {
        switch option {
        case .light: .white
        case .dark: Color(white: 0.30)
        case .system: Color(white: 0.55)
        }
    }
}
