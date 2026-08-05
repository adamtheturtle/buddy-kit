//
//  InlineEditableTitle.swift
//  BuddyDesignSystem
//
//  The inline-editable detail title, lifted from the coderpad and HackerRank apps
//  (#637) and unified here. A heading that doubles as an editable text field: it
//  reads as a plain title until hovered or focused, when a subtle pencil fades in to
//  signal it can be edited in place; clicking it (or the pencil) turns it into a
//  field that commits on Return or focus-loss, writing optimistically through
//  `onCommit`.
//
//  Adopts the HackerRank app's self-owning, callback-based shape (`title: String` +
//  an async `onCommit`) — the view owns its own focus and draft, so the host just
//  supplies the value and a commit closure — while keeping the coderpad app's
//  optional split-view width clamp and iPad persistent-pencil affordance behind
//  parameters.
//

import SwiftUI

/// The pure commit decision for an inline edit, factored out so it can be unit-tested
/// without a running view. `nonisolated` (it's a pure function) so a plain, non-`@MainActor`
/// test or caller can use it without hopping to the main actor.
public nonisolated enum InlineEdit {
    /// The value to write when committing an edit, or `nil` when nothing should be
    /// written — the text is unchanged (ignoring surrounding whitespace) or empty.
    /// Returns the trimmed value so a rename never writes leading/trailing spaces.
    public static func commitValue(original: String, edited: String) -> String? {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != original.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return trimmed
    }

    static func editingRemainsAllowed(isEditing: Bool, editingAllowed: Bool) -> Bool {
        isEditing && editingAllowed
    }
}

/// Tracks whether an inline edit already owns the single commit slot. Both Return
/// and focus loss can arrive in the same run-loop turn, so the event handler must
/// claim the slot synchronously before it creates any asynchronous work.
nonisolated struct InlineEditCommitGate {
    private(set) var isClaimed = false

    mutating func claim() -> Bool {
        guard !isClaimed else { return false }

        isClaimed = true
        return true
    }

    mutating func release() {
        isClaimed = false
    }
}

/// A title that reads as a plain heading until hovered/focused, then edits in place,
/// committing on Return or focus-loss. Self-owning: it holds its own focus and draft
/// and writes optimistically through `onCommit`, so the host only supplies the value
/// and the commit closure. Editing is offered only when `isEditable` is true *and*
/// the environment isn't read-only.
public struct InlineEditableTitle: View {
    private let title: String
    private let placeholder: LocalizedStringKey
    private let isEditable: Bool
    private let clampsWidth: Bool
    private let font: Font
    /// Writes the new value, returning whether it succeeded; a failure reverts to the
    /// title (the host keeps the old value, so reverting is just leaving edit mode).
    private let onCommit: (String) async -> Bool

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovering = false
    @State private var commitGate = InlineEditCommitGate()
    @FocusState private var fieldFocused: Bool

    /// While offline the app is read-only, so the title isn't editable (#321).
    @Environment(\.isReadOnly) private var isReadOnly
    /// Drop the pencil fade-in when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The title's natural (untruncated) width, and the row's available width. Used
    /// only when `clampsWidth` is set (see `fieldWidth`).
    @State private var naturalWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    /// Room reserved at the trailing edge for the pencil hint plus its spacing, so a
    /// truncated title doesn't run right up against (or under) the pencil.
    private static let pencilReserve: CGFloat = 28

    /// - Parameters:
    ///   - title: The current title (the host's stored value, shown at rest).
    ///   - placeholder: The field's prompt when the title is empty.
    ///   - isEditable: Whether editing is offered at all (e.g. a writable entity on a
    ///     live/demo account). Editing also requires the environment not be read-only.
    ///   - clampsWidth: When true, the editing field is clamped to the title's natural
    ///     width capped to the available row width, so a long title truncates rather
    ///     than inflating an enclosing split-view column (coderpad #429). Off by
    ///     default — a form-embedded title (HackerRank) wants the plain flexible field.
    ///   - font: The heading font. Defaults to `.title2.weight(.semibold)`.
    ///   - onCommit: Writes the new value, returning whether it succeeded.
    public init(
        title: String,
        placeholder: LocalizedStringKey = "Name",
        isEditable: Bool = true,
        clampsWidth: Bool = false,
        font: Font = .title2.weight(.semibold),
        onCommit: @escaping (String) async -> Bool
    ) {
        self.title = title
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.clampsWidth = clampsWidth
        self.font = font
        self.onCommit = onCommit
    }

    /// Editing is only offered when the host allows it *and* the environment isn't
    /// read-only.
    private var editingAllowed: Bool {
        isEditable && !isReadOnly
    }

    /// The pencil is a hint, not a control. Hidden while editing isn't allowed. On
    /// macOS it appears only while the row is hovered or the field is focused, keeping
    /// the header clean otherwise. iPad has no hover, so a hover-gated pencil would
    /// never show and the title would read as non-editable — there it's shown
    /// persistently, matching the other inline editors' touch affordances (#597).
    private var showsPencil: Bool {
        guard editingAllowed else { return false }
        #if os(macOS)
            return isHovering
        #else
            return true
        #endif
    }

    /// Width to pin the field to when `clampsWidth` is set: the title's natural width,
    /// clamped to what the row can show. `nil` until both measurements arrive (and for
    /// an empty title), leaving the field flexible so the placeholder still shows.
    private var fieldWidth: CGFloat? {
        guard clampsWidth, naturalWidth > 0, availableWidth > 0 else { return nil }

        return min(naturalWidth, max(0, availableWidth - Self.pencilReserve))
    }

    public var body: some View {
        Group {
            if InlineEdit.editingRemainsAllowed(isEditing: isEditing, editingAllowed: editingAllowed) {
                editorField
            } else if editingAllowed {
                editableTitle
            } else {
                plainTitle
            }
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: editingAllowed) { _, allowed in
            if !allowed { cancelEditing() }
        }
    }

    /// The static title shown in read-only contexts — identical to a plain header.
    private var plainTitle: some View {
        Text(title)
            #if !os(tvOS)
                .textSelection(.enabled)
            #endif
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The at-rest title that reveals a pencil on hover (or persistently on iPad) and
    /// begins editing on click.
    private var editableTitle: some View {
        HStack(spacing: 6) {
            Text(title)
                #if !os(tvOS)
                    .textSelection(.enabled)
                #endif
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(clampsWidth ? 1 : nil)
                .truncationMode(.tail)
                .frame(maxWidth: fieldWidth, alignment: .leading)
                .background {
                    if clampsWidth { titleWidthReader }
                }

            Image(systemName: "pencil")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(showsPencil ? 1 : 0)
                // The ~17pt pencil is shown persistently on iPad, so give it a 44pt hit
                // area on touch (no-op on macOS, #597), and highlight it under the iPad
                // pointer (#586).
                .touchTarget()
                .pointerHoverEffect()
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        #if !os(tvOS)
            .onHover { isHovering = $0 }
        #endif
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: showsPencil)
        // The whole title is the affordance, so a click anywhere on it begins editing.
        .onTapGesture { beginEditing() }
        .help("Click to rename")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edit title")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private var editorField: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .disabled(commitGate.isClaimed)
                .lineLimit(1)
                .frame(maxWidth: fieldWidth, alignment: .leading)
                .onSubmit { requestCommit() }
                // Commit when focus leaves the field (clicking elsewhere).
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { requestCommit() }
                }

            if commitGate.isClaimed {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// Measures the title's natural width from a hidden, `fixedSize` copy of the text
    /// so the reported value is the untruncated width even while the visible title is
    /// clamped and line-limited. Only attached when `clampsWidth` is set.
    private var titleWidthReader: some View {
        Text(title)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
    }

    private func beginEditing() {
        guard editingAllowed else { return }

        draft = title
        isEditing = true
        fieldFocused = true
    }

    private func requestCommit() {
        guard InlineEdit.editingRemainsAllowed(isEditing: isEditing, editingAllowed: editingAllowed) else {
            cancelEditing()
            return
        }
        guard let value = InlineEdit.commitValue(original: title, edited: draft) else {
            // No change (or empty): just leave edit mode without writing.
            isEditing = false
            return
        }
        guard commitGate.claim() else { return }

        Task {
            let succeeded = await onCommit(value)
            commitGate.release()
            isEditing = false
            // On failure the host keeps the old title, so reverting is just leaving edit mode.
            _ = succeeded
        }
    }

    private func cancelEditing() {
        isEditing = false
        fieldFocused = false
    }
}
