import Foundation
import AetherEngine

/// Host policy for the upscale stage (`LoadOptions.upscalesLowResolutionVideo`, AetherEngine#846, and
/// `upscaleScaler`, #1039).
///
/// Sodalite picks the line-art scaler per title from the server's genres. A local file has no genre,
/// so here it is the viewer's choice: on for anime and cartoons, off again for live action, which the
/// line-art network paints over. Stored as two switches so the long-standing upscaling key keeps
/// its meaning for anyone who had it on.
enum UpscalingSetting: String, CaseIterable, Identifiable {
    case off, on, lineArt
    var id: String { rawValue }

    static let enabledKey = "playback.enhancedUpscaling"
    static let lineArtKey = "playback.lineArtUpscaling"

    init(enabled: Bool, lineArt: Bool) {
        self = !enabled ? .off : (lineArt ? .lineArt : .on)
    }

    static func current(defaults: UserDefaults = .standard) -> UpscalingSetting {
        UpscalingSetting(enabled: defaults.bool(forKey: enabledKey), lineArt: defaults.bool(forKey: lineArtKey))
    }

    var upscales: Bool { self != .off }

    var scaler: UpscaleScaler { self == .lineArt ? .lineArt : .automatic }

    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .on: String(localized: "On")
        case .lineArt: String(localized: "Animation (line art)")
        }
    }
}
