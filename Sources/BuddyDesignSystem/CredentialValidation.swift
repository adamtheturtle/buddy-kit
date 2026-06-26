//
//  CredentialValidation.swift
//  BuddyDesignSystem
//
//  The shared slice of two apps' account editors: the four-state validation status of a
//  credential (API key / token) being checked against its backend, and the small banner
//  that presents it. Both apps duplicated this enum + banner near-identically; the editor
//  shells, field sets and save flows differ too much to share, so only this presentation
//  is extracted.
//

import SwiftUI

/// The status of validating a credential against its backend. Detail-free on `.valid`
/// (an app that wants to surface, say, an org name keeps it in its own state) so the
/// shared type stays domain-neutral.
public nonisolated enum CredentialValidationState: Equatable, Sendable {
    case idle
    case validating
    case valid
    case invalid(String)
}

/// Presents a `CredentialValidationState`: nothing while idle; a small spinner with
/// `validating` text while checking; a green checkmark with `success` text on success
/// (or nothing, when `success` is nil — for a key whose success is shown only by enabling
/// Save); a red error label carrying the message on failure.
public struct ValidationStatusBanner: View {
    private let state: CredentialValidationState
    private let validatingText: LocalizedStringKey
    private let successText: LocalizedStringKey?

    public init(
        _ state: CredentialValidationState,
        validating validatingText: LocalizedStringKey,
        success successText: LocalizedStringKey? = nil
    ) {
        self.state = state
        self.validatingText = validatingText
        self.successText = successText
    }

    @ViewBuilder
    public var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(validatingText).foregroundStyle(.secondary)
            }
            .font(.callout)

        case .valid:
            if let successText {
                Label(successText, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            } else {
                EmptyView()
            }

        case let .invalid(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout)
        }
    }
}
