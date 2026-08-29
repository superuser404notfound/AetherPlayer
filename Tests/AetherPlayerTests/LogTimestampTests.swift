import XCTest
@testable import AetherPlayer

/// The stamp on every diagnostics line is a machine-readable field: it gets diffed against a server log
/// and against a log handed over from Sodalite, which emits the identical format. So these pin the exact
/// bytes, and they pin the cases a hand-rolled calendar gets wrong, since this one does not go through
/// `DateFormatter`.
final class LogTimestampTests: XCTestCase {

    func testKnownInstants() {
        let cases: [(Double, String)] = [
            (0, "1970-01-01T00:00:00.000Z"),
            (1_756_386_191.482, "2025-08-28T13:03:11.482Z"),
            (951_782_400, "2000-02-29T00:00:00.000Z"),
            (1_709_164_800, "2024-02-29T00:00:00.000Z"),
            // 2100 is divisible by 4 and NOT a leap year, the case a naive leap rule gets wrong.
            (4_107_542_400, "2100-03-01T00:00:00.000Z"),
            (1_767_225_599.999, "2025-12-31T23:59:59.999Z"),
            (1_767_225_600, "2026-01-01T00:00:00.000Z"),
        ]
        for (epoch, expected) in cases {
            XCTAssertEqual(LogTimestamp.stamp(Date(timeIntervalSince1970: epoch)), expected)
        }
    }

    /// A stamp that changes length knocks the message column out of alignment for every line below it.
    func testFixedWidth() {
        for epoch in [0.0, -1.0, 1_756_386_191.482, 4_107_542_400.0, 253_402_300_799.0] {
            let stamp = LogTimestamp.stamp(Date(timeIntervalSince1970: epoch))
            XCTAssertEqual(stamp.count, LogTimestamp.width, "\(stamp)")
        }
    }

    /// Sub-millisecond precision rounds rather than truncating, and the rounding has to carry into the
    /// second or the log would show 11.000 inside minute 03.
    func testRoundingCarries() {
        XCTAssertEqual(LogTimestamp.stamp(Date(timeIntervalSince1970: 1_756_386_191.4819)), "2025-08-28T13:03:11.482Z")
        XCTAssertEqual(LogTimestamp.stamp(Date(timeIntervalSince1970: 1_756_386_191.9996)), "2025-08-28T13:03:12.000Z")
    }

    /// Not reachable from a live clock, reachable from a Mac whose date is unset. A truncating division
    /// would put a negative millisecond in the field and print garbage.
    func testBeforeEpoch() {
        XCTAssertEqual(LogTimestamp.stamp(Date(timeIntervalSince1970: -1)), "1969-12-31T23:59:59.000Z")
        XCTAssertEqual(LogTimestamp.stamp(Date(timeIntervalSince1970: -0.25)), "1969-12-31T23:59:59.750Z")
    }

    /// The calendar arithmetic is hand-rolled, so it is worth holding against the one in the SDK rather
    /// than only against values a human typed. Every 100000th second from 1970 to 2100.
    func testAgreesWithISO8601FormatterAcrossACentury() {
        let reference = ISO8601DateFormatter()
        reference.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        reference.timeZone = TimeZone(identifier: "UTC")

        var epoch = 0.0
        while epoch < 4_102_444_800 {
            let date = Date(timeIntervalSince1970: epoch)
            XCTAssertEqual(LogTimestamp.stamp(date), reference.string(from: date), "at epoch \(epoch)")
            epoch += 100_000
        }
    }
}
