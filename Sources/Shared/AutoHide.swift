import Foundation

/// True when the transport bar should hide: more than `interval` seconds
/// have elapsed since the last user activity. Boundary is inclusive-visible
/// (exactly `interval` elapsed keeps it visible).
func shouldHideControls(now: TimeInterval, lastActivity: TimeInterval, interval: TimeInterval) -> Bool {
    (now - lastActivity) > interval
}

func shouldHideCursor(controlsVisible: Bool, isFullScreen: Bool) -> Bool {
    !controlsVisible && isFullScreen
}
