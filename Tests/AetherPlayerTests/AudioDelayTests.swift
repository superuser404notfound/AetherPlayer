import Testing
import Foundation
@testable import AetherPlayer

/// The lip-sync nudge's pure half: what a press does to the value, and what the value reads as.
struct AudioDelayTests {

    @Test func startsAtZeroAndSteps() {
        #expect(AudioDelay.adjusted(0, by: AudioDelay.step) == 0.05)
        #expect(AudioDelay.adjusted(0, by: -AudioDelay.step) == -0.05)
    }

    @Test func stopsAtTheCeilingInBothDirections() {
        #expect(AudioDelay.adjusted(AudioDelay.maxAbsSeconds, by: AudioDelay.step) == AudioDelay.maxAbsSeconds)
        #expect(AudioDelay.adjusted(-AudioDelay.maxAbsSeconds, by: -AudioDelay.step) == -AudioDelay.maxAbsSeconds)
    }

    /// A run of presses out and back has to land exactly where it started. Accumulating 0.05 in binary
    /// does not, which is what the millisecond snap is for: without it the label reads "+0 ms" over a
    /// value that is not zero, and the Reset item stays enabled with nothing to reset.
    @Test func aRoundTripReturnsToExactlyZero() {
        var value: Double = 0
        for _ in 0 ..< 7 { value = AudioDelay.adjusted(value, by: AudioDelay.step) }
        for _ in 0 ..< 7 { value = AudioDelay.adjusted(value, by: -AudioDelay.step) }
        #expect(value == 0)
    }

    /// A defaults read is a plain Double and can be anything a downgrade or a hand-edited plist left
    /// behind. A finite value out of range is a delay someone asked too much of, so it clamps; a
    /// non-finite one is not a delay at all and becomes no correction, which is also what the engine's
    /// own `AudioDelayPolicy.clamp` does with it. The two have to agree or this UI would show a ceiling
    /// value over a session running at zero.
    @Test func clampTakesWhateverTheDefaultsHold() {
        #expect(AudioDelay.clamp(9) == AudioDelay.maxAbsSeconds)
        #expect(AudioDelay.clamp(-9) == -AudioDelay.maxAbsSeconds)
        #expect(AudioDelay.clamp(.nan) == 0)
        #expect(AudioDelay.clamp(.infinity) == 0)
        #expect(AudioDelay.clamp(-.infinity) == 0)
        #expect(AudioDelay.clamp(0.12) == 0.12)
    }

    @Test func labelsCarryTheirSignExceptAtZero() {
        #expect(AudioDelay.label(0) == "0 ms")
        #expect(AudioDelay.label(0.05) == "+50 ms")
        #expect(AudioDelay.label(-0.15) == "-150 ms")
        #expect(AudioDelay.label(2) == "+2000 ms")
    }

    /// A value alone does not say which stream moved, so the on-screen line names the direction.
    @Test func theNoticeNamesTheDirection() {
        #expect(AudioDelay.noticeText(0.05).contains("audio later"))
        #expect(AudioDelay.noticeText(-0.05).contains("audio earlier"))
        #expect(AudioDelay.noticeText(0) == "Audio delay 0 ms")
    }
}
