import CoreGraphics

/// User-facing subtitle size choices. `rawValue` is persisted in UserDefaults
/// under "player.subtitleSize".
enum SubtitleSize: String, CaseIterable, Identifiable {
    case small, normal, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return String(localized: "Small")
        case .normal: return String(localized: "Normal")
        case .large: return String(localized: "Large")
        case .extraLarge: return String(localized: "Extra Large")
        }
    }

    /// Multiplier applied on top of the surface-relative auto scale.
    var scale: CGFloat {
        switch self {
        case .small: return 0.75
        case .normal: return 1.0
        case .large: return 1.5
        case .extraLarge: return 2.0
        }
    }
}

/// Subtitle point size at the 1080p reference surface height.
let subtitleBaseFontSize: CGFloat = 24

/// Effective subtitle font size. Scales linearly with the rendered surface
/// height relative to a 1080p reference so a 27" fullscreen surface gets a
/// proportionally larger caption, then applies the user's size choice. The
/// auto factor is clamped to [0.5, 3.0] so tiny and oversized surfaces stay
/// legible without runaway text.
func subtitleFontSize(surfaceHeight: CGFloat, userScale: CGFloat,
                      base: CGFloat = subtitleBaseFontSize) -> CGFloat {
    guard surfaceHeight > 0 else { return base * userScale }
    let auto = min(max(surfaceHeight / 1080, 0.5), 3.0)
    return base * auto * userScale
}
