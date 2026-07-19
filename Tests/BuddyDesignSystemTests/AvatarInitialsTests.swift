//
//  AvatarInitialsTests.swift
//  BuddyDesignSystemTests
//
//  Covers the initials derivation behind ``AvatarCircle`` (#11), which moved out of
//  `body` into `init` and switched from rewriting the string twice to a single split.
//  These pin the behaviour so the rewrite is equivalent.
//

@testable import BuddyDesignSystem
import Testing

struct AvatarInitialsTests {
    @Test func `a full name initials to two letters`() {
        #expect(AvatarCircle.initials(from: "Basil Fawlty") == "BF")
    }

    @Test func `a single name initials to one letter`() {
        #expect(AvatarCircle.initials(from: "Manuel") == "M")
    }

    @Test func `only the first two words are used`() {
        #expect(AvatarCircle.initials(from: "Basil Sybil Fawlty") == "BS")
    }

    @Test func `an email address initials from its local part`() {
        // `@` and `.` are separators, so this reads as "basil fawlty", not "bf.co".
        #expect(AvatarCircle.initials(from: "basil.fawlty@example.com") == "BF")
    }

    @Test func `a bare address without dots uses the local part and domain`() {
        #expect(AvatarCircle.initials(from: "basil@example.com") == "BE")
    }

    @Test func `results are uppercased`() {
        #expect(AvatarCircle.initials(from: "ada lovelace") == "AL")
    }

    @Test func `empty or separator-only labels fall back to a question mark`() {
        #expect(AvatarCircle.initials(from: "") == "?")
        #expect(AvatarCircle.initials(from: "   ") == "?")
        #expect(AvatarCircle.initials(from: "@.") == "?")
    }

    @Test func `extra whitespace between words is ignored`() {
        #expect(AvatarCircle.initials(from: "  Basil   Fawlty  ") == "BF")
    }

    @Test func `the derived value is stored on the view`() {
        // The point of #11: `body` reads a stored value rather than recomputing.
        #expect(AvatarCircle(label: "Basil Fawlty").initials == "BF")
    }
}
