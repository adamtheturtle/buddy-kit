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
}
