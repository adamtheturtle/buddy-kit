//
//  DocumentPrinter.swift
//  BuddyDesignSystem
//
//  The domain-neutral print / Save-as-PDF core, lifted from the coderpad app. SwiftUI
//  has no print pipeline of its own, so a print-friendly view is rasterized with
//  `ImageRenderer` and handed to the platform print machinery (`NSPrintOperation` on
//  macOS, `UIPrintInteractionController` on iOS). The app builds its own
//  document-shaped views from the `PrintSection`/`PrintCode` layout primitives here.
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

#if os(macOS)
    /// Renders `content` to paper through the standard macOS print panel. The view is
    /// rasterized at the printable page width with `ImageRenderer`, and `NSPrintOperation`
    /// paginates the resulting image down the page automatically.
    ///
    /// Why rasterize rather than print an `NSHostingView` directly: `NSPrintOperation`
    /// captures a view through its `draw(_:)` path, but a layer-backed `NSHostingView`'s
    /// SwiftUI content isn't emitted there, so printing it yields a blank page. Drawing the
    /// rendered image in a plain `NSView.draw(_:)` is captured correctly.
    ///
    /// The content is pinned to a light color scheme on a white background: paper is white,
    /// and adaptive colors would otherwise print as whatever the current appearance happens
    /// to be (white-on-white in dark mode).
    @MainActor
    public func printDocument(_ content: some View, jobTitle: String) {
        let info = NSPrintInfo()
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let contentWidth = info.paperSize.width - info.leftMargin - info.rightMargin

        let document = content
            .frame(width: contentWidth, alignment: .leading)
            .environment(\.colorScheme, .light)
            .background(Color.white)

        let renderer = ImageRenderer(content: document)
        renderer.scale = 2 // crisp text on paper rather than screen-resolution bitmap
        guard let image = renderer.nsImage else { return }

        let operation = NSPrintOperation(view: PrintImageView(image: image), printInfo: info)
        operation.jobTitle = jobTitle
        operation.run()
    }

    /// A plain image-drawing view for printing. `NSPrintOperation` paginates it down the page
    /// via repeated `draw(_:)` calls - the standard view-drawing path, which (unlike a hosted
    /// SwiftUI view's layer) is captured into the print context. Flipped so the image's top
    /// lands on the first page.
    private final class PrintImageView: NSView {
        private let image: NSImage

        init(image: NSImage) {
            self.image = image
            super.init(frame: NSRect(origin: .zero, size: image.size))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override var isFlipped: Bool {
            true
        }

        override func draw(_: NSRect) {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
    }
#else
    /// iPad printing through the standard `UIPrintInteractionController`. The same
    /// `ImageRenderer` rasterization used on macOS produces a `UIImage`, which is a
    /// valid printing item - UIKit paginates the image across pages on its own.
    ///
    /// The content is pinned to a light color scheme on a white background for the same
    /// reason as macOS: paper is white, so adaptive colors shouldn't print as dark mode.
    @MainActor
    public func printDocument(_ content: some View, jobTitle: String) {
        let document = content
            .environment(\.colorScheme, .light)
            .background(Color.white)

        let renderer = ImageRenderer(content: document)
        renderer.scale = 2 // crisp text on paper rather than screen-resolution bitmap
        guard let image = renderer.uiImage else { return }

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobTitle
        info.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
        controller.present(animated: true)
    }
#endif

// MARK: - Print layout primitives

/// A titled block in a printed document - a small heading over its content, with
/// space below so sections don't run together across a page.
public struct PrintSection<Content: View>: View {
    private let title: String
    @ViewBuilder private let content: () -> Content

    public init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Code rendered for paper: plain wrapping monospaced text rather than an on-screen
/// syntax-highlighted, horizontally-scrolling view (which wouldn't paginate). Wrapping
/// keeps long lines on the page instead of clipping them.
public struct PrintCode: View {
    private let code: String

    public init(code: String) {
        self.code = code
    }

    public var body: some View {
        Text(code)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
