import Foundation

/// Host policy for the lip-sync nudge (AetherEngine AE#464, `setAudioDelay`).
///
/// The offset belongs to the viewer's chain (a soundbar or an AVR adding video-processing latency,
/// Bluetooth headphones adding audio latency) rather than to any one file, so it is set once and
/// applied to every session: the value is persisted, handed to each `load` as
/// `LoadOptions.audioDelaySeconds`, and a change made while something is playing goes to the running
/// session through `setAudioDelay`.
///
/// `maxAbsSeconds` mirrors the engine's `AudioDelayPolicy.maxAbsSeconds`, which is internal to the
/// package. A divergence could not produce a wrong offset, the engine clamps whatever arrives, but it
/// would let this UI offer a value the engine silently trims, so the two are stated to be the same
/// number here rather than left to drift.
enum AudioDelay {

    /// Largest offset either direction, in seconds.
    static let maxAbsSeconds: Double = 2.0

    /// One press. Lip-sync error people actually notice starts around 40 ms of audio lead, so a step
    /// finer than this costs presses without buying a distinction anyone can hear.
    static let step: Double = 0.05

    /// Bring a value into range. A non-finite value (a NaN out of a stale defaults read) becomes 0
    /// rather than travelling on into a timestamp.
    static func clamp(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, -maxAbsSeconds), maxAbsSeconds)
    }

    /// The value after one adjustment, clamped and snapped to whole milliseconds. The snap is what
    /// keeps a long run of presses from accumulating binary-fraction dust into a label that reads
    /// "+149 ms" after three steps up and three steps back.
    static func adjusted(_ current: Double, by delta: Double) -> Double {
        clamp((clamp(current) + delta).roundedToMilliseconds)
    }

    /// Signed milliseconds, the unit every other player states this in. Zero carries no sign because
    /// it names the absence of a correction, not a direction.
    static func label(_ seconds: Double) -> String {
        let ms = Int((clamp(seconds) * 1000).rounded())
        if ms == 0 { return "0 ms" }
        return ms > 0 ? "+\(ms) ms" : "\(ms) ms"
    }

    /// What the on-screen line says when the value changes. Names the direction, because "+150 ms"
    /// alone does not say which of the two streams moved.
    static func noticeText(_ seconds: Double) -> String {
        let value = label(seconds)
        let ms = Int((clamp(seconds) * 1000).rounded())
        if ms == 0 { return "Audio delay \(value)" }
        return ms > 0 ? "Audio delay \(value) (audio later)" : "Audio delay \(value) (audio earlier)"
    }
}

private extension Double {
    var roundedToMilliseconds: Double { (self * 1000).rounded() / 1000 }
}
