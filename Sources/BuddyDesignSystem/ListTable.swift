//
//  ListTable.swift
//  BuddyDesignSystem
//
//  The NSTableView-backed list now lives in its own OSS package, FastList
//  (https://github.com/adamtheturtle/FastList), so the engine has a single source of
//  truth. This file is a thin compatibility wrapper that preserves buddy-kit's existing
//  `ListTable` / `RowMenuItem` / `RowSwipeAction` API — so the consuming apps compile
//  unchanged — while delegating all behavior to FastList.
//

import AppKit
import FastList
import SwiftUI

/// One entry in a row's right-click menu (preserved buddy-kit API; maps to a
/// `FastList.MenuItem`). `isDestructive` is carried for source compatibility but, as
/// before, has no distinct visual treatment in the native menu.
public enum RowMenuItem {
    case button(title: String, isDestructive: Bool = false, isEnabled: Bool = true, perform: () -> Void)
    case separator
}

/// One swipe action on a row edge (preserved buddy-kit API; maps to a
/// `FastList.SwipeAction`). Keeps the `NSColor` tint and `isDestructive` flag the apps
/// already pass.
public struct RowSwipeAction {
    var title: String
    var isDestructive: Bool
    var tint: NSColor?
    var systemImage: String?
    var perform: () -> Void

    public init(
        title: String,
        isDestructive: Bool = false,
        tint: NSColor? = nil,
        systemImage: String? = nil,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.tint = tint
        self.systemImage = systemImage
        self.perform = perform
    }
}

/// An `NSTableView`-backed list — see ``FastList`` for the implementation. Unlike SwiftUI
/// `List`, an `NSTableView` materializes and recycles only the visible rows, so selection
/// is near-instant regardless of length.
///
/// The hosted row content must be hit-transparent except its interactive controls (apply
/// `.allowsHitTesting(false)` to the non-interactive parts) so left-clicks fall through to
/// the table for native selection.
public struct ListTable<Item: Identifiable>: View where Item.ID: Hashable {
    var items: [Item]
    @Binding var selection: Set<Item.ID>
    var scrollToID: Item.ID?
    var onScrolledToID: () -> Void
    var rowContent: (Item) -> AnyView
    var onDoubleClick: (Item) -> Void
    var onReturn: (Item) -> Void
    var leadingActions: (Item) -> [RowSwipeAction]
    var trailingActions: (Item) -> [RowSwipeAction]
    var pasteboardItem: (Item) -> NSPasteboardItem?
    var menuItems: (Item) -> [RowMenuItem]
    var onTopRowChange: ((Item.ID?) -> Void)?
    var onDragSessionBegan: (NSDraggingSession) -> Void
    var onDragSessionEnded: () -> Void

    public init(
        items: [Item],
        selection: Binding<Set<Item.ID>>,
        scrollToID: Item.ID? = nil,
        onScrolledToID: @escaping () -> Void,
        rowContent: @escaping (Item) -> AnyView,
        onDoubleClick: @escaping (Item) -> Void,
        onReturn: @escaping (Item) -> Void,
        leadingActions: @escaping (Item) -> [RowSwipeAction],
        trailingActions: @escaping (Item) -> [RowSwipeAction],
        pasteboardItem: @escaping (Item) -> NSPasteboardItem?,
        menuItems: @escaping (Item) -> [RowMenuItem],
        onTopRowChange: ((Item.ID?) -> Void)? = nil,
        onDragSessionBegan: @escaping (NSDraggingSession) -> Void = { _ in },
        onDragSessionEnded: @escaping () -> Void = {}
    ) {
        self.items = items
        _selection = selection
        self.scrollToID = scrollToID
        self.onScrolledToID = onScrolledToID
        self.rowContent = rowContent
        self.onDoubleClick = onDoubleClick
        self.onReturn = onReturn
        self.leadingActions = leadingActions
        self.trailingActions = trailingActions
        self.pasteboardItem = pasteboardItem
        self.menuItems = menuItems
        self.onTopRowChange = onTopRowChange
        self.onDragSessionBegan = onDragSessionBegan
        self.onDragSessionEnded = onDragSessionEnded
    }

    public var body: some View {
        var list = FastList(items, selection: $selection, row: rowContent)
            .onDoubleClick(onDoubleClick)
            .onReturnKey(onReturn)
            .swipeActions(edge: .leading) { mapSwipe(leadingActions($0)) }
            .swipeActions(edge: .trailing) { mapSwipe(trailingActions($0)) }
            .onRowDrag(pasteboardItem)
            .rowContextMenu { mapMenu(menuItems($0)) }
            .onDragSession(began: onDragSessionBegan, ended: onDragSessionEnded)
            .scrollToRow(id: scrollToID, then: onScrolledToID)
        if let onTopRowChange {
            list = list.onTopRowChange(onTopRowChange)
        }
        return list
    }

    private func mapSwipe(_ actions: [RowSwipeAction]) -> [SwipeAction] {
        actions.map { action in
            SwipeAction(
                title: action.title,
                role: action.isDestructive ? .destructive : .normal,
                tint: action.tint.map { Color(nsColor: $0) },
                systemImage: action.systemImage,
                action: action.perform
            )
        }
    }

    private func mapMenu(_ entries: [RowMenuItem]) -> [MenuItem] {
        entries.map { entry in
            switch entry {
            case let .button(title, _, isEnabled, perform):
                return .button(title: title, isEnabled: isEnabled, action: perform)
            case .separator:
                return .separator
            }
        }
    }
}
