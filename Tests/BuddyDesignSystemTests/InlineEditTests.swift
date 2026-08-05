//
//  InlineEditTests.swift
//  BuddyDesignSystemTests
//
//  Covers the pure commit-decision logic behind ``InlineEditableTitle`` (#637): a
//  rename should commit the trimmed value only when it actually changes, and never
//  write empty or whitespace-only text. Factored out of the view so it needs no
//  running UI.
//

@testable import BuddyDesignSystem
import Testing

struct InlineEditTests {
    @Test func `a changed value commits trimmed`() {
        #expect(InlineEdit.commitValue(original: "Old", edited: "  New Name  ") == "New Name")
    }

    @Test func `an unchanged value does not commit`() {
        #expect(InlineEdit.commitValue(original: "Same", edited: "Same") == nil)
    }

    @Test func `a value differing only by whitespace does not commit`() {
        #expect(InlineEdit.commitValue(original: "Name", edited: "  Name  ") == nil)
    }

    @Test func `an empty or whitespace value does not commit`() {
        #expect(InlineEdit.commitValue(original: "Name", edited: "") == nil)
        #expect(InlineEdit.commitValue(original: "Name", edited: "   ") == nil)
    }

    // A `nonisolated` test proves `commitValue` is callable from a non-`@MainActor`
    // context (#5); it would not compile if the function were MainActor-isolated.
    @Test nonisolated func `commitValue is callable from a nonisolated context`() {
        #expect(InlineEdit.commitValue(original: "Old", edited: "New") == "New")
    }

    @Test nonisolated func `return-triggered focus loss cannot claim a second commit`() {
        var gate = InlineEditCommitGate()

        // Return claims the commit slot synchronously. SwiftUI can then report the
        // field's resulting focus loss before the asynchronous save finishes.
        let returnClaimed = gate.claim()
        let focusLossClaimed = gate.claim()
        #expect(returnClaimed)
        #expect(!focusLossClaimed)

        gate.release()
        let nextEditClaimed = gate.claim()
        #expect(nextEditClaimed)
    }

    @Test nonisolated func `becoming read-only ends editing and blocks commit`() {
        #expect(InlineEdit.editingRemainsAllowed(isEditing: true, editingAllowed: true))
        #expect(!InlineEdit.editingRemainsAllowed(isEditing: true, editingAllowed: false))
    }
}
