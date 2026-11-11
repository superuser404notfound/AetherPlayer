import CoreGraphics

/// Pure gesture-to-intent mappers for the iOS touch player, shared by the SwiftUI gesture catcher
/// and unit tests. The actual gestures live in SwiftUI (PlayerGestureCatcher) so they sit in the
/// overlay's z-order below the controls and above the video.
/// A two-finger trackpad swipe as both apps see it: each horizontal step (the first carries the
/// travel so far), then its end. Vertical swipes never arrive here.
enum TrackpadScrubEvent { case moved(deltaX: CGFloat), ended, cancelled }

enum PlayerTouchInput {
    /// Left third -> -interval, right third -> +interval, middle -> nil (handled as play/pause).
    static func skipSeconds(forTapX x: CGFloat, width: CGFloat, interval: Double) -> Double? {
        guard width > 0 else { return nil }
        if x < width / 3 { return -interval }
        if x > width * 2 / 3 { return interval }
        return nil
    }

    /// Upward drag raises the level. Returns a signed fraction of the drag height (unclamped; callers clamp).
    static func levelDelta(translationY: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return 0 }
        return Double(-translationY / height)
    }

    /// Which edge strip a vertical drag starts in. Left strip = brightness, right strip = volume;
    /// the wide center is a dead zone so a minimize / other swipe there never changes a level.
    enum PanZone { case brightness, volume, none }

    /// Classify a drag's start X. The strip is `edgeFraction` of the width at each edge.
    static func zone(forStartX x: CGFloat, width: CGFloat, edgeFraction: CGFloat = 0.18) -> PanZone {
        guard width > 0 else { return .none }
        let edge = width * edgeFraction
        if x < edge { return .brightness }
        if x > width - edge { return .volume }
        return .none
    }

    /// Horizontal trackpad travel, in points, that spans the full timeline. Fixed rather than the
    /// view's width: how far fingers move on a trackpad has nothing to do with the window's size.
    static let trackpadScrubPointsPerTimeline: CGFloat = 4_000

    /// Two-finger trackpad scrub: one step of the swipe moves the scrub on from where it already is.
    /// Clamped to 0...1 at every step, so travel past either end is dropped.
    static func scrubFraction(from current: Double, deltaX: CGFloat) -> Double {
        min(max(current + Double(deltaX / trackpadScrubPointsPerTimeline), 0), 1)
    }
}
