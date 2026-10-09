import XCTest
@testable import Fade

final class FormattingTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func date(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: string)!
    }

    func testRelativeShort() {
        let now = date("2026-10-09T12:00:00Z")
        XCTAssertEqual(RelativeTime.short(from: date("2026-10-09T11:59:40Z"), to: now, calendar: calendar), "now")
        XCTAssertEqual(RelativeTime.short(from: date("2026-10-09T11:56:00Z"), to: now, calendar: calendar), "4m")
        XCTAssertEqual(RelativeTime.short(from: date("2026-10-09T09:00:00Z"), to: now, calendar: calendar), "3h")
        XCTAssertEqual(RelativeTime.short(from: date("2026-10-07T12:00:00Z"), to: now, calendar: calendar), "2d")
        XCTAssertEqual(RelativeTime.short(from: date("2026-09-20T12:00:00Z"), to: now, calendar: calendar), "Sep 20")
    }

    func testRemaining() {
        let now = date("2026-10-09T12:00:00Z")
        XCTAssertEqual(RelativeTime.remaining(until: date("2026-10-10T09:00:00Z"), from: now), "21h")
        XCTAssertEqual(RelativeTime.remaining(until: date("2026-10-09T12:35:00Z"), from: now), "35m")
        XCTAssertEqual(RelativeTime.remaining(until: date("2026-10-09T11:00:00Z"), from: now), "closed")
    }

    func testGameTimeLabels() {
        let now = date("2026-10-09T12:00:00Z")           // a Friday
        XCTAssertEqual(GameTime.label(date("2026-10-09T19:00:00Z"), now: now, calendar: calendar), "Tonight 7:00 PM")
        XCTAssertEqual(GameTime.label(date("2026-10-09T13:05:00Z"), now: now, calendar: calendar), "Today 1:05 PM")
        XCTAssertEqual(GameTime.label(date("2026-10-10T15:00:00Z"), now: now, calendar: calendar), "Tomorrow 3:00 PM")
        XCTAssertEqual(GameTime.label(date("2026-10-12T19:30:00Z"), now: now, calendar: calendar), "Mon 7:30 PM")
        XCTAssertEqual(GameTime.label(date("2026-10-25T19:00:00Z"), now: now, calendar: calendar), "Oct 25, 7:00 PM")
    }

    func testDayTitles() {
        let now = date("2026-10-09T12:00:00Z")
        XCTAssertEqual(GameTime.dayTitle(date("2026-10-09T23:00:00Z"), now: now, calendar: calendar), "Today")
        XCTAssertEqual(GameTime.dayTitle(date("2026-10-10T23:00:00Z"), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(GameTime.dayTitle(date("2026-10-11T23:00:00Z"), now: now, calendar: calendar), "Sunday, Oct 11")
    }
}

final class AvatarTests: XCTestCase {
    func testSameNameSameColourAlways() {
        XCTAssertEqual(AvatarPalette.hue(for: "maya"), AvatarPalette.hue(for: "@Maya "))
        XCTAssertTrue(AvatarPalette.hues.contains(AvatarPalette.hue(for: "theo")))
    }

    func testDifferentNamesSpreadAcrossColours() {
        let names = ["maya", "theo", "jules", "dre", "sam", "riley", "alex", "kim", "pat", "lee", "jo", "max"]
        XCTAssertGreaterThan(Set(names.map { AvatarPalette.hue(for: $0) }).count, 2)
    }

    func testInitials() {
        XCTAssertEqual(AvatarPalette.initials("maya"), "M")
        XCTAssertEqual(AvatarPalette.initials("@dylan", count: 2), "DY")
        XCTAssertEqual(AvatarPalette.initials(""), "?")
        XCTAssertEqual(AvatarPalette.groupInitials("College Boys"), "CB")
        XCTAssertEqual(AvatarPalette.groupInitials("Fam"), "FA")
        XCTAssertEqual(AvatarPalette.groupInitials("Work Pool League"), "WP")
    }
}
