import Foundation

/// The UTC stamp `DiagnosticsLog` writes in front of every line it appends.
///
/// A twin of the file by the same name in Sodalite, deliberately duplicated rather than pushed into
/// AetherEngine: three of the four sinks that read `EngineLog.handler` already carry a time (Console
/// stamps OSLog itself, `aetherctl live` prints a relative offset that is the better reading for a repro
/// run), so an engine-side stamp would be a policy two consumers immediately opt out of. Both apps
/// emitting the SAME format is what matters, because a log handed over from one gets diffed against a
/// log from the other. Keep the two copies identical; only this comment differs.
///
/// Computed straight from the epoch rather than through a `DateFormatter`, because a formatter carries a
/// locale and a calendar: one that forgets `en_US_POSIX` prints Eastern Arabic digits for an Arabic user,
/// and one that forgets an explicit Gregorian calendar prints year 1447 for a Hijri one. This field
/// exists to be diffed against a server log and handed to an AI, so it has to come out byte-identical on
/// every device.
nonisolated enum LogTimestamp {

    /// Character count of every stamp, no exceptions. Fixed width is the point: the message column only
    /// lines up in the monospaced view if the stamp never changes length, which is also why the year is
    /// padded rather than clamped.
    static let width = 24

    /// `2026-08-28T14:03:11.482Z`, always 24 ASCII characters.
    ///
    /// Millisecond resolution because the races these logs get read for (a segment fetch against the
    /// AVPlayer failure that follows it) happen inside a single second, and a stamp that can only say
    /// "same second" answers none of them.
    static func stamp(_ date: Date = Date()) -> String {
        // Rounded, not truncated: the caller's Date carries far more precision than three digits, and
        // truncating would report .481 for a moment that is .4819.
        let totalMillis = Int64((date.timeIntervalSince1970 * 1000).rounded())

        // Floor division rather than Swift's truncating `/`, so a pre-1970 date walks backwards instead
        // of landing on a negative millisecond. Not reachable from a live clock, reachable from a test.
        var seconds = totalMillis / 1000
        var millis = totalMillis % 1000
        if millis < 0 {
            millis += 1000
            seconds -= 1
        }

        var days = seconds / 86_400
        var secondOfDay = seconds % 86_400
        if secondOfDay < 0 {
            secondOfDay += 86_400
            days -= 1
        }

        let (year, month, day) = civilFromDays(days)

        var bytes = [UInt8]()
        bytes.reserveCapacity(width)
        append(year, digits: 4, to: &bytes)
        bytes.append(UInt8(ascii: "-"))
        append(month, digits: 2, to: &bytes)
        bytes.append(UInt8(ascii: "-"))
        append(day, digits: 2, to: &bytes)
        bytes.append(UInt8(ascii: "T"))
        append(secondOfDay / 3600, digits: 2, to: &bytes)
        bytes.append(UInt8(ascii: ":"))
        append((secondOfDay % 3600) / 60, digits: 2, to: &bytes)
        bytes.append(UInt8(ascii: ":"))
        append(secondOfDay % 60, digits: 2, to: &bytes)
        bytes.append(UInt8(ascii: "."))
        append(millis, digits: 3, to: &bytes)
        bytes.append(UInt8(ascii: "Z"))
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Gregorian year/month/day for a count of days since 1970-01-01, via Howard Hinnant's
    /// `civil_from_days`. Shifting the epoch to March 1st (the `719468`) is what lets the month lengths
    /// fall out of one linear expression, because the leap day then sits at the end of the year rather
    /// than in the middle of it.
    private static func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097                                                    // [0, 146096]
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let shiftedYear = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)       // [0, 365]
        let monthPortion = (5 * dayOfYear + 2) / 153                                        // [0, 11]
        let day = dayOfYear - (153 * monthPortion + 2) / 5 + 1                              // [1, 31]
        let month = monthPortion < 10 ? monthPortion + 3 : monthPortion - 9                 // [1, 12]
        return (month <= 2 ? shiftedYear + 1 : shiftedYear, month, day)
    }

    /// Zero-padded decimal. A value too wide for its field keeps its low digits, so a nonsense date
    /// cannot silently shorten the stamp and knock the whole column out of line.
    private static func append(_ value: Int64, digits: Int, to bytes: inout [UInt8]) {
        var scale: Int64 = 1
        for _ in 1 ..< digits { scale *= 10 }
        var remainder = value < 0 ? 0 : value % (scale * 10)
        while scale > 0 {
            bytes.append(UInt8(ascii: "0") + UInt8(remainder / scale))
            remainder %= scale
            scale /= 10
        }
    }
}
