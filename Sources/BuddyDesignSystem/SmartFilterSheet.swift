//
//  SmartFilterSheet.swift
//  BuddyDesignSystem
//
//  The natural-language "smart filter" entry sheet, lifted from the coderpad app
//  (#636) and shared with the HackerRank app. It takes a plain-language query and
//  hands it to the host, which asks its on-device interpreter to turn it into the
//  list's filters. This view is only the entry surface: a field, an interpreting
//  state, and a plain explanation when the model couldn't map the request to
//  anything. The host owns the interpretation and the filter bindings.
//
//  Domain-free: the caller supplies the placeholder, the submit/cancel handlers,
//  and — because the error copy and success hint read differently per app — the
//  `failedMessage` and `hintMessage` labels.
//

import SwiftUI

/// A small sheet that takes a natural-language query and asks the host to interpret
/// it into filters. Shared by both apps' pad/question lists so the entry surface
/// stays identical; each supplies its own placeholder, messages, and handlers.
public struct SmartFilterSheet: View {
    @Binding private var text: String
    private let isInterpreting: Bool
    private let failed: Bool
    private let placeholder: LocalizedStringKey
    private let failedMessage: LocalizedStringKey
    private let hintMessage: LocalizedStringKey
    private let onSubmit: () -> Void
    private let onCancel: () -> Void

    /// On iPad a plain `.sheet` is a fixed-size form card, so this short content
    /// would float in a large empty box. We measure the content's natural height
    /// and pin the sheet to a matching detent. macOS sheets already size to fit.
    @State private var contentHeight: CGFloat = 0

    /// - Parameters:
    ///   - text: The natural-language query (two-way bound so the host reads it back).
    ///   - isInterpreting: True while the on-device model is interpreting, so the
    ///     Apply button shows a spinner and both actions disable.
    ///   - failed: True after an attempt the model couldn't map to any filter, so the
    ///     sheet shows `failedMessage` instead of silently closing.
    ///   - placeholder: The field's prompt (e.g. an example query).
    ///   - failedMessage: The warning shown after a no-match attempt. Differs per app.
    ///   - hintMessage: The success/idle hint below the field. Differs per app.
    ///   - onSubmit: Interprets the current query. Called on Return and on Apply.
    ///   - onCancel: Dismisses the sheet without interpreting.
    public init(
        text: Binding<String>,
        isInterpreting: Bool,
        failed: Bool,
        placeholder: LocalizedStringKey,
        failedMessage: LocalizedStringKey,
        hintMessage: LocalizedStringKey,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _text = text
        self.isInterpreting = isInterpreting
        self.failed = failed
        self.placeholder = placeholder
        self.failedMessage = failedMessage
        self.hintMessage = hintMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    /// The trimmed query; empty means there's nothing to interpret, so Apply/submit
    /// are suppressed.
    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        content
        #if os(iOS)
            .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.medium])
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: $text, prompt: Text(placeholder), axis: .vertical)
                    #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                    .lineLimit(2 ... 4)
                    .font(.body)
                    .onSubmit(onSubmit)
                    .disabled(isInterpreting)
                if failed {
                    Label(failedMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label(hintMessage, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 440)
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        #endif
    }

    /// A tinted sparkles glyph beside the title and a one-line explanation, so the
    /// sheet reads as a labelled feature rather than a bare text box.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Filter")
                    .font(.headline)
                Text("Describe what you want in plain language and it becomes filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
            Button(action: onSubmit) {
                if isInterpreting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Apply")
                }
            }
            #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
            #endif
            .buttonStyle(.borderedProminent)
            .disabled(isInterpreting || trimmed.isEmpty)
        }
    }
}
