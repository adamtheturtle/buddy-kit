//
//  Tokens.swift
//  BuddyDesignSystem
//
//  Colour, spacing, and contrast tokens shared across the design-system primitives.
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

public extension Color {
    #if os(macOS)
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
    #elseif os(tvOS)
        static let cardBackground = Color.primary.opacity(0.08)
    #else
        static let cardBackground = Color(uiColor: .secondarySystemBackground)
    #endif
    static let subtleStroke = Color.primary.opacity(0.08)
    /// The neutral capsule fill an *idle* filter chip wears on macOS 15 so every chip
    /// in the bar reads as a control rather than bare text + chevron (#352). On
    /// macOS 26 the chips use Liquid Glass instead; this is the fallback, bumped from
    /// a near-invisible 6% so it still plainly reads as a filled control on Sequoia.
    static let chipIdleFill = Color.primary.opacity(0.11)

    /// Parses an "#RRGGBB" (or "RRGGBB") hex string into an sRGB color, or `nil` if
    /// it isn't a well-formed six-digit hex value.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }

        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// This color as an "#RRGGBB" sRGB hex string, or `nil` if it can't be resolved
    /// to fixed components (e.g. a dynamic/catalog color).
    var hexString: String? {
        #if os(macOS)
            guard let resolved = NSColor(self).usingColorSpace(.sRGB) else { return nil }

            let red = Int((resolved.redComponent * 255).rounded())
            let green = Int((resolved.greenComponent * 255).rounded())
            let blue = Int((resolved.blueComponent * 255).rounded())
            return String(format: "#%02X%02X%02X", red, green, blue)
        #else
            // UIColor has no color-space conversion that can fail the same way; read
            // the sRGB components directly, returning nil if they can't be resolved.
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }

            return String(
                format: "#%02X%02X%02X",
                Int((red * 255).rounded()),
                Int((green * 255).rounded()),
                Int((blue * 255).rounded())
            )
        #endif
    }
}

/// Shared corner radii so cards, chips, and controls curve consistently instead of
/// each view reaching for its own magic number. Named by the role a shape plays
/// rather than its value; tweak here to restyle a whole tier at once (#629). Lifted
/// from the app so shared controls (the saved-search chip) can reference the same
/// scale instead of hard-coding a radius.
public enum Radius {
    /// Tightly nested inner fills (e.g. an appearance swatch inside a selected card).
    public static let tight: CGFloat = 4
    /// Compact controls: chips, tokens, and small pills.
    public static let chip: CGFloat = 6
    /// Standard controls, selectable rows, and small cards.
    public static let control: CGFloat = 8
    /// Content cards and media/code thumbnails.
    public static let card: CGFloat = 10
    /// Prominent hero and empty-state cards.
    public static let prominent: CGFloat = 16
}

/// Shared layout constants so pane chrome stays in sync across detail views.
/// Tweak these here instead of hunting for matching literals in every view.
public enum Spacing {
    /// Horizontal inset for pane content.
    public static let paneH: CGFloat = 22
    /// Vertical inset for pane content (its top gap below the toolbar and its
    /// bottom padding).
    public static let paneV: CGFloat = 22
    /// Interior padding for ``Card``.
    public static let card: CGFloat = 16
    /// Horizontal inset for the inline banner.
    public static let bannerH: CGFloat = 14
}

/// Contrast-aware opacities for the app's tinted chips and badges. Their default
/// fills are deliberately subtle; under the system "Increase Contrast"
/// accessibility setting they're raised (and the hairline stroke thickened) so
/// the controls stay legible for low-vision users.
public enum ChipContrast {
    public static func fill(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.2) : base
    }

    public static func stroke(_ base: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, base * 2.4) : base
    }

    public static func lineWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 1 : 0.5
    }
}
