//
//  DockBadge.swift
//  BuddyAppKit
//
//  A tiny seam over the Dock-icon badge count (#645). Both interview apps render a
//  count on the Dock tile (active pads / scheduled interviews); only the *derivation* of
//  the count differs, so that stays app-side and this shares just the rendering. A nil /
//  zero count clears the badge so "nothing to show" leaves a clean icon rather than a
//  "0". A no-op on iOS, which has no Dock.
//

#if os(macOS)
    import AppKit
#endif

public enum DockBadge {
    /// Set the Dock badge to `count`, or clear it when `count <= 0`. Must be called on
    /// the main actor (it touches `NSApp.dockTile`). `display()` forces the tile to
    /// redraw, since setting `badgeLabel` alone doesn't always refresh a tile already on
    /// screen.
    @MainActor
    public static func set(count: Int) {
        #if os(macOS)
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
            NSApp.dockTile.display()
        #else
            _ = count
        #endif
    }
}
