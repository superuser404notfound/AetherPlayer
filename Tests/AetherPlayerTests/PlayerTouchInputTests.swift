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
    @Test func trackpadScrubMovesByWidthFraction() {
        #expect(PlayerTouchInput.scrubFraction(start: 0.5, translationX: 100, width: 400) == 0.75)
        #expect(PlayerTouchInput.scrubFraction(start: 0.5, translationX: -100, width: 400) == 0.25)
    }
    @Test func trackpadScrubClampsToTimeline() {
        #expect(PlayerTouchInput.scrubFraction(start: 0.9, translationX: 400, width: 400) == 1)
        #expect(PlayerTouchInput.scrubFraction(start: 0.1, translationX: -400, width: 400) == 0)
    }
    @Test func trackpadScrubZeroWidthKeepsStart() {
        #expect(PlayerTouchInput.scrubFraction(start: 0.3, translationX: 50, width: 0) == 0.3)
    }
}
