import Testing
import CoreGraphics
@testable import AetherPlayer

struct PlayerTouchInputTests {
    @Test func leftThirdSkipsBack() {
        #expect(PlayerTouchInput.skipSeconds(forTapX: 10, width: 300, interval: 10) == -10)
    }
    @Test func rightThirdSkipsForward() {
        #expect(PlayerTouchInput.skipSeconds(forTapX: 290, width: 300, interval: 10) == 10)
    }
    @Test func centerIsNil() {
        #expect(PlayerTouchInput.skipSeconds(forTapX: 150, width: 300, interval: 10) == nil)
    }
    @Test func zeroWidthIsNil() {
        #expect(PlayerTouchInput.skipSeconds(forTapX: 10, width: 0, interval: 10) == nil)
    }
    @Test func levelDeltaUpwardRaises() {
        #expect(PlayerTouchInput.levelDelta(translationY: -50, height: 100) == 0.5)
    }
    @Test func levelDeltaDownwardLowers() {
        #expect(PlayerTouchInput.levelDelta(translationY: 25, height: 100) == -0.25)
    }
    @Test func levelDeltaZeroHeightIsZero() {
        #expect(PlayerTouchInput.levelDelta(translationY: -50, height: 0) == 0)
    }
    @Test func zoneLeftStripIsBrightness() {
        #expect(PlayerTouchInput.zone(forStartX: 10, width: 300) == .brightness)
    }
    @Test func zoneRightStripIsVolume() {
        #expect(PlayerTouchInput.zone(forStartX: 290, width: 300) == .volume)
    }
    @Test func zoneCenterIsNone() {
        #expect(PlayerTouchInput.zone(forStartX: 150, width: 300) == .none)
    }
    @Test func zoneBoundaryJustInsideLeftEdge() {
        // edge = 300 * 0.18 = 54; x = 53 is inside the brightness strip.
        #expect(PlayerTouchInput.zone(forStartX: 53, width: 300) == .brightness)
    }
    @Test func zoneRightBoundaryJustInsideEdge() {
        #expect(PlayerTouchInput.zone(forStartX: 247, width: 300) == .volume)
    }
    @Test func zoneRightBoundaryAtEdgeIsNone() {
        #expect(PlayerTouchInput.zone(forStartX: 246, width: 300) == .none)
    }
    @Test func zoneZeroWidthIsNone() {
        #expect(PlayerTouchInput.zone(forStartX: 10, width: 0) == .none)
    }
    @Test func trackpadScrubMovesByFixedTravel() {
        let quarter = PlayerTouchInput.trackpadScrubPointsPerTimeline / 4
        #expect(PlayerTouchInput.scrubFraction(from: 0.5, deltaX: quarter) == 0.75)
        #expect(PlayerTouchInput.scrubFraction(from: 0.5, deltaX: -quarter) == 0.25)
    }
    @Test func trackpadScrubClampsToTimeline() {
        let full = PlayerTouchInput.trackpadScrubPointsPerTimeline
        #expect(PlayerTouchInput.scrubFraction(from: 0.9, deltaX: full) == 1)
        #expect(PlayerTouchInput.scrubFraction(from: 0.1, deltaX: -full) == 0)
    }
    @Test func trackpadScrubStopsShortOfTheEnd() {
        let full = PlayerTouchInput.trackpadScrubPointsPerTimeline
        let limit = PlayerTouchInput.trackpadScrubLimit(duration: 100)
        #expect(limit == 1 - PlayerTouchInput.trackpadScrubEndMargin / 100)
        #expect(PlayerTouchInput.scrubFraction(from: 0.9, deltaX: full, upTo: limit) == limit)
        // A file shorter than twice the margin still scrubs through its first half.
        #expect(PlayerTouchInput.trackpadScrubLimit(duration: 4) == 0.5)
        #expect(PlayerTouchInput.trackpadScrubLimit(duration: 0) == 1)
    }
    @Test func trackpadScrubPicksDirectionAfterLockDistance() {
        let lock = PlayerTouchInput.trackpadScrubAxisLockDistance
        #expect(PlayerTouchInput.trackpadScrubIsHorizontal(travelX: lock - 0.1, travelY: 0) == nil)
        #expect(PlayerTouchInput.trackpadScrubIsHorizontal(travelX: -lock, travelY: 1) == true)
        #expect(PlayerTouchInput.trackpadScrubIsHorizontal(travelX: 1, travelY: lock) == false)
        #expect(PlayerTouchInput.trackpadScrubIsHorizontal(travelX: lock, travelY: -lock) == false)
    }
}
