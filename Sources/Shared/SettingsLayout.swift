import CoreGraphics

/// Maximum height for the macOS Settings window's content, so the window stays on screen and the
/// rest scrolls. `visibleHeight` is the screen's `visibleFrame` height, which already excludes the
/// menu bar and Dock; `inset` leaves room for the window's title bar and a margin. Never below
/// `minimum`, so a few rows stay visible on the smallest screens.
func settingsWindowMaxHeight(visibleHeight: CGFloat, inset: CGFloat = 80,
                             minimum: CGFloat = 320) -> CGFloat {
    max(minimum, visibleHeight - inset)
}
