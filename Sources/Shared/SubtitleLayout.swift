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

// MARK: - Appearance (issue #9)

/// UserDefaults keys for the subtitle appearance. Read through `@AppStorage` by the overlay, the
/// menus and the settings screen alike, so a change in any of them applies to the line on screen.
enum SubtitleAppearanceKey {
    static let size = "player.subtitleSize"
    static let font = "player.subtitleFont"
    static let weight = "player.subtitleWeight"
    static let color = "player.subtitleColor"
    static let background = "player.subtitleBackground"
    static let position = "player.subtitlePosition"
    /// Default true: ASS/SSA tracks draw with the fonts, colours and placement they ship with.
    static let embeddedStyles = "player.subtitleEmbeddedStyles"
}

/// Text cues only; bitmap and styled ASS subtitles carry their own typeface.
enum SubtitleFont: String, CaseIterable, Identifiable {
    case system, highLegibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .highLegibility: return String(localized: "High Legibility")
        }
    }
}

enum SubtitleWeight: String, CaseIterable, Identifiable {
    case regular, bold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular: return String(localized: "Regular")
        case .bold: return String(localized: "Bold")
        }
    }
}

enum SubtitleTextColor: String, CaseIterable, Identifiable {
    case white, yellow, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: return String(localized: "White")
        case .yellow: return String(localized: "Yellow")
        case .gray: return String(localized: "Gray")
        }
    }
}

/// How a text line separates from the picture. `.box` is the look the app always had.
enum SubtitleBackground: String, CaseIterable, Identifiable {
    case box, outline, shadow, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .box: return String(localized: "Box")
        case .outline: return String(localized: "Outline")
        case .shadow: return String(localized: "Shadow")
        case .none: return String(localized: "None")
        }
    }
}

/// Where text cues sit, and how far bitmap cues move with them. `.standard` keeps the historical
/// text gap and leaves bitmap cues where the disc authored them.
enum SubtitlePosition: String, CaseIterable, Identifiable {
    case standard, bottom, low, midLow, mid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return String(localized: "Default")
        case .bottom: return String(localized: "Bottom Edge")
        case .low: return String(localized: "Low")
        case .midLow: return String(localized: "Mid-Low")
        case .mid: return String(localized: "Mid")
        }
    }

    /// Fraction of the surface height between its bottom edge and the text block; nil = default.
    var fractionFromBottom: CGFloat? {
        switch self {
        case .standard: return nil
        case .bottom: return 0
        case .low: return 0.10
        case .midLow: return 0.20
        case .mid: return 0.30
        }
    }
}

/// Historical gap between the surface bottom and a text cue, kept as the `.standard` position.
let subtitleDefaultBottomInset: CGFloat = 48
/// Smallest gap at `.bottom`, so a box or outline is not cut off by the window edge.
let subtitleMinimumBottomInset: CGFloat = 8

/// Distance from the surface bottom to the bottom of the text block.
func subtitleBottomInset(position: SubtitlePosition, surfaceHeight: CGFloat) -> CGFloat {
    guard let fraction = position.fractionFromBottom else { return subtitleDefaultBottomInset }
    return max(subtitleMinimumBottomInset, fraction * surfaceHeight)
}

/// Vertical shift for bitmap cues under a non-default position. Bitmaps move by the same fraction
/// the text does; `.standard` and `.bottom` leave the authored layout alone.
func subtitleBitmapShift(position: SubtitlePosition, surfaceHeight: CGFloat) -> CGFloat {
    -(position.fractionFromBottom ?? 0) * surfaceHeight
}

/// Outline stroke width, grown with the text so a 4K fullscreen line keeps a solid edge.
func subtitleOutlineWidth(pointSize: CGFloat) -> CGFloat {
    max(1, pointSize / 14)
}
