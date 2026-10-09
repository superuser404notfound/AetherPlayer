import Foundation

/// The speed control's pure half: which speeds exist, and where a step up or down from the current one
/// lands. The keys and the menu walk the same list the transport bar's picker offers, so a press never
/// produces a value the picker cannot tick.
enum PlaybackSpeed {

    /// Every speed the UI offers, slowest first.
    static let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    static let normal: Float = 1.0

    /// The next listed speed above `current`, or nil at the top. A value between two entries (none of
    /// ours, but the engine clamps and a future picker may not) steps to the nearer entry in that
    /// direction rather than skipping one.
    static func faster(than current: Float) -> Float? {
        rates.first { $0 > current }
    }

    /// The next listed speed below `current`, or nil at the bottom.
    static func slower(than current: Float) -> Float? {
        rates.last { $0 < current }
    }

    static func noticeText(_ rate: Float) -> String {
        String(localized: "Speed \(rateLabel(rate))")
    }
}
