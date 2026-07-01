//
//  WindowRepresentedURL.swift
//  BuddyAppKit
//
//  A domain-free `NSViewRepresentable` that binds the enclosing window's proxy-icon URL
//  (`NSWindow.representedURL`) to a value (#645). Dropping it into a window's content
//  gives the title bar the small draggable proxy icon that Finder-style documents show,
//  pointing at the supplied URL. An iOS no-op keeps cross-platform call sites compiling
//  (iOS windows have no title bar or proxy icon).
//

import SwiftUI

#if os(macOS)
    import AppKit

    /// A zero-size representable whose only job is to reach its host `NSWindow` and set
    /// its `representedURL` (the title-bar proxy icon). Re-runs on every SwiftUI update,
    /// so a changing URL keeps the proxy icon in sync.
    public struct WindowRepresentedURL: NSViewRepresentable {
        private let url: URL?

        public init(_ url: URL?) {
            self.url = url
        }

        public func makeNSView(context: Context) -> NSView {
            let view = NSView(frame: .zero)
            // Defer to the next run loop: the view isn't attached to a window yet during
            // `makeNSView`, so reading `view.window` now would be nil.
            DispatchQueue.main.async { [weak view] in
                view?.window?.representedURL = url
            }
            return view
        }

        public func updateNSView(_ nsView: NSView, context: Context) {
            nsView.window?.representedURL = url
        }
    }
#else
    /// iOS has no window title bar or proxy icon, so this is an inert placeholder that
    /// keeps shared call sites compiling.
    public struct WindowRepresentedURL: View {
        public init(_ url: URL?) {
            _ = url
        }

        public var body: some View {
            EmptyView()
        }
    }
#endif
