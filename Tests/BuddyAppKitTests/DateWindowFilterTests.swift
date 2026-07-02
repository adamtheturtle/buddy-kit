//
//  DateWindowFilterTests.swift
//  BuddyAppKitTests
//
//  Ported from the coderpad pad-list-logic suite: the named date-range lower bounds,
//  the date-window containment, and the generic filter seam.
//

import BuddyAppKit
import Foundation
import Testing

/// A fixed clock so the date-range tests don't depend on the wall clock, and a UTC
/// calendar so `startOfDay` lands on a known instant regardless of the machine's
/// time zone.
private let fixedNow = ISO8601DateFormatter().date(from: "2026-06-12T12:00:00Z") ?? .distantPast
private var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return cal
}

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string) ?? .distantPast
}

@Suite("Named date range")
struct NamedDateRangeTests {
    @Test
    func `today starts at midnight of the current day`() {
        #expect(NamedDateRange.start(for: "today", now: fixedNow, calendar: utcCalendar)
            == iso("2026-06-12T00:00:00Z"))
    }

    @Test
    func `last 24 hours rolls back exactly one day from now`() {
        #expect(NamedDateRange.start(for: "last 24 hours", now: fixedNow, calendar: utcCalendar)
            == iso("2026-06-11T12:00:00Z"))
    }

    @Test
    func `last 7 days anchors to midnight, today plus six prior days`() {
        #expect(NamedDateRange.start(for: "last 7 days", now: fixedNow, calendar: utcCalendar)
            == iso("2026-06-06T00:00:00Z"))
    }

    @Test
    func `last 30 days anchors to midnight, today plus twenty-nine prior days`() {
        #expect(NamedDateRange.start(for: "last 30 days", now: fixedNow, calendar: utcCalendar)
            == iso("2026-05-14T00:00:00Z"))
    }

    @Test
    func `last 90 days anchors to midnight, today plus eighty-nine prior days`() {
        #expect(NamedDateRange.start(for: "last 90 days", now: fixedNow, calendar: utcCalendar)
            == iso("2026-03-15T00:00:00Z"))
    }

    @Test
    func `an unrecognized option imposes no lower bound`() {
        #expect(NamedDateRange.start(for: "all time", now: fixedNow) == nil)
        #expect(NamedDateRange.start(for: "", now: fixedNow) == nil)
    }

    @Test
    func `the chip options match the recognized keys`() {
        for option in NamedDateRange.options {
            #expect(NamedDateRange.start(for: option, now: fixedNow) != nil)
        }
    }
}

@Suite("Date window")
struct DateWindowTests {
    @Test
    func `an inactive window contains everything`() {
        let window = DateWindow()
        #expect(!window.isActive)
        #expect(window.contains(.distantPast, now: fixedNow))
        #expect(window.contains(.distantFuture, now: fixedNow))
    }

    @Test
    func `a named window excludes values before its lower bound`() {
        let window = DateWindow(range: "last 7 days")
        #expect(window.isActive)
        #expect(!window.contains(iso("2026-06-01T12:00:00Z"), now: fixedNow))
        #expect(window.contains(iso("2026-06-10T12:00:00Z"), now: fixedNow))
    }

    @Test
    func `a custom range overrides the named window and bounds both ends inclusively`() {
        let window = DateWindow(range: "today",
                                customStart: iso("2026-06-01T00:00:00Z"),
                                customEnd: iso("2026-06-05T00:00:00Z"))
        // Custom start wins over the "today" named bound, so an early-June value passes.
        #expect(window.contains(iso("2026-06-03T00:00:00Z"), now: fixedNow))
        #expect(window.contains(iso("2026-06-05T00:00:00Z"), now: fixedNow))
        #expect(!window.contains(iso("2026-06-06T00:00:00Z"), now: fixedNow))
        #expect(!window.contains(iso("2026-05-31T00:00:00Z"), now: fixedNow))
    }

    @Test
    func `the signature token distinguishes two different custom ranges`() {
        let a = DateWindow(customStart: iso("2026-06-01T00:00:00Z"))
        let b = DateWindow(customStart: iso("2026-06-02T00:00:00Z"))
        #expect(a.signatureToken != b.signatureToken)
        #expect(DateWindow().signatureToken == DateWindow().signatureToken)
    }

    @Test
    func `it round-trips through Codable`() throws {
        let window = DateWindow(range: "last 30 days", customEnd: iso("2026-06-05T00:00:00Z"))
        let data = try JSONEncoder().encode(window)
        #expect(try JSONDecoder().decode(DateWindow.self, from: data) == window)
    }
}

@Suite("List filter criteria seam")
struct ListFilterCriteriaTests {
    private struct Row: Equatable {
        let name: String
        let createdAt: Date
    }

    private struct Criteria: ListFilterCriteria {
        let search: String
        let created: DateWindow
        nonisolated func matches(_ item: Row, now: Date) -> Bool {
            (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
                && created.contains(item.createdAt, now: now)
        }
    }

    @Test
    func `filtered applies the criteria predicate over a sequence`() {
        let rows = [
            Row(name: "Alpha", createdAt: iso("2026-06-10T12:00:00Z")),
            Row(name: "Beta", createdAt: iso("2026-06-01T12:00:00Z")),
            Row(name: "Gamma", createdAt: iso("2026-06-11T12:00:00Z"))
        ]
        let criteria = Criteria(search: "a", created: DateWindow(range: "last 7 days"))
        let result = rows.filtered(by: criteria, now: fixedNow)
        // All three names contain an "a", but "Beta" falls outside the 7-day window, so
        // only "Alpha" and "Gamma" survive — and original order is preserved.
        #expect(result.map(\.name) == ["Alpha", "Gamma"])
    }
}
