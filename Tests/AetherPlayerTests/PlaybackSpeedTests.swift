import Testing
@testable import AetherPlayer

/// Where a speed key lands. The ends matter most: a press past them has to be a no-op the menu can
/// grey out, not a value outside the picker.
struct PlaybackSpeedTests {

    @Test func stepsWalkTheListInOrder() {
        #expect(PlaybackSpeed.faster(than: 1.0) == 1.25)
        #expect(PlaybackSpeed.slower(than: 1.0) == 0.75)
        #expect(PlaybackSpeed.faster(than: 0.5) == 0.75)
        #expect(PlaybackSpeed.slower(than: 2.0) == 1.5)
    }

    @Test func stopsAtBothEnds() {
        #expect(PlaybackSpeed.faster(than: 2.0) == nil)
        #expect(PlaybackSpeed.slower(than: 0.5) == nil)
    }

    @Test func aValueBetweenEntriesStepsToTheNearerOne() {
        #expect(PlaybackSpeed.faster(than: 1.1) == 1.25)
        #expect(PlaybackSpeed.slower(than: 1.1) == 1.0)
    }

    @Test func coversTheRangeTheIssueAskedFor() {
        #expect(PlaybackSpeed.rates.first == 0.5)
        #expect(PlaybackSpeed.rates.last == 2.0)
        #expect(PlaybackSpeed.rates.contains(PlaybackSpeed.normal))
    }
}
