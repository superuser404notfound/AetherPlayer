import AetherEngine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Figure-dash placeholder for an unavailable value.
private let statsPlaceholder = "\u{2012}"

func formatResolution(width: Int, height: Int) -> String {
    guard width > 0, height > 0 else { return statsPlaceholder }
    return "\(width) \u{00D7} \(height)"
}

func videoFormatLabel(_ format: VideoFormat) -> String {
    switch format {
    case .sdr: return "SDR"
    case .hdr10: return "HDR10"
    case .hdr10Plus: return "HDR10+"
    case .dolbyVision: return "Dolby Vision"
    case .hlg: return "HLG"
    @unknown default: return statsPlaceholder
    }
}

/// HDR label refined with the Dolby Vision profile number when present ("Dolby Vision P5").
func hdrLabel(_ format: VideoFormat, dvProfile: Int?) -> String {
    if format == .dolbyVision, let profile = dvProfile {
        return "Dolby Vision P\(profile)"
    }
    return videoFormatLabel(format)
}

/// Source dynamic range, showing the panel-negotiated result when the engine clamps it (DV/HDR source on an
/// SDR panel renders "Dolby Vision P5 \u{2192} SDR"). `source` is `sourceVideoFormat`, `effective` is `videoFormat`.
/// A Profile 7 presented as Dolby Vision is served as Profile 8.1, so the target names that profile (AE#459).
func dynamicRangeLabel(
    source: VideoFormat,
    effective: VideoFormat,
    dvProfile: Int?,
    conversion: DolbyVisionConversion? = nil
) -> String {
    let s = hdrLabel(source, dvProfile: dvProfile)
    if effective == .dolbyVision, conversion == .profile7ToProfile81 {
        return "\(s) \u{2192} P8.1"
    }
    let e = hdrLabel(effective, dvProfile: dvProfile)
    return s == e ? s : "\(s) \u{2192} \(e)"
}

/// Nominal source frame rate. Snaps near-integer rates ("24 fps") and keeps three decimals otherwise ("23.976 fps").
func formatFrameRate(_ value: Double?) -> String {
    guard let value, value > 0 else { return statsPlaceholder }
    let rounded = value.rounded()
    if abs(value - rounded) < 0.01 {
        return String(format: "%.0f fps", rounded)
    }
    return String(format: "%.3f fps", value)
}

/// Channel layout with an Atmos suffix when the active track carries JOC ("5.1 \u{00B7} Atmos").
/// AE#658: "48 kHz", "44.1 kHz"; placeholder when the stream declares none.
func formatSampleRate(_ hz: Int) -> String {
    guard hz > 0 else { return statsPlaceholder }
    return hz % 1000 == 0 ? "\(hz / 1000) kHz" : String(format: "%.1f kHz", Double(hz) / 1000)
}

/// Placeholder for 0 / nil, which the engine uses where a codec has no fixed depth.
func formatBitDepth(_ bits: Int?) -> String {
    guard let bits, bits > 0 else { return statsPlaceholder }
    return "\(bits)-bit"
}

/// Codec name with the engine's profile appended, "HEVC · Main 10", "DTS · DTS-HD MA + DTS:X".
func formatCodec(_ codec: String?, profile: String?) -> String {
    guard let codec, !codec.isEmpty else { return statsPlaceholder }
    guard let profile, !profile.isEmpty else { return codec.uppercased() }
    return "\(codec.uppercased()) \u{00B7} \(profile)"
}

func formatChannels(_ channels: Int, isAtmos: Bool) -> String {
    guard channels > 0 else { return statsPlaceholder }
    let layout: String
    switch channels {
    case 1: layout = String(localized: "Mono")
    case 2: layout = String(localized: "Stereo")
    case 6: layout = "5.1"
    case 8: layout = "7.1"
    default: layout = "\(channels)ch"
    }
    return isAtmos ? "\(layout) \u{00B7} Atmos" : layout
}

/// Declared stream bitrate in bits/second. Placeholder for 0 (container left it unset, e.g. lossless VBR).
func formatBitrateBps(_ bps: Int64) -> String {
    guard bps > 0 else { return statsPlaceholder }
    let mbps = Double(bps) / 1_000_000
    if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
    return "\(bps / 1000) kbps"
}

/// Current panel dynamic-range mode from the display's EDR headroom. `> 1.0` means the built-in/external
/// display is in its extended-range (HDR/Dolby Vision) mode; the exact "+DV" split lives in the Dynamic Range row.
func currentDisplayModeLabel() -> String {
    #if os(macOS)
    guard let screen = NSScreen.main else { return statsPlaceholder }
    let edr = screen.maximumExtendedDynamicRangeColorComponentValue
    if edr > 1.0 {
        return String(format: "HDR \u{00B7} EDR %.1f\u{00D7}", edr)
    }
    return "SDR"
    #else
    // iOS: no NSScreen/EDR-headroom equivalent is wired up yet; the Stats
    // panel shows a placeholder here until an iOS dynamic-range read exists.
    return statsPlaceholder
    #endif
}

func formatMbps(_ value: Double?) -> String {
    guard let value else { return statsPlaceholder }
    return String(format: "%.1f Mbps", value)
}

func formatFps(_ value: Double?) -> String {
    guard let value else { return statsPlaceholder }
    return String(format: "%.1f fps", value)
}

func formatDroppedFrames(_ value: Int?) -> String {
    guard let value else { return statsPlaceholder }
    return "\(value)"
}

func formatSeconds(_ value: Double?) -> String {
    guard let value else { return statsPlaceholder }
    return String(format: "%.1f s", value)
}

func formatMemoryMB(_ mb: Int) -> String {
    "\(mb) MB"
}

/// How the session's audio reaches the renderer (AetherEngine AE#462). Names the pipeline rather than
/// the enum case, since the row is read next to the decoder row: "Bitstream" means the authored
/// bitstream arrived untouched, "Bridged" means it was re-encoded to get through fMP4, and "Dropped"
/// is the one value that says the session is playing silently and why.
func formatAudioDelivery(_ delivery: AudioDelivery) -> String {
    switch delivery {
    case .none: return statsPlaceholder
    case .noAudioInSource: return String(localized: "None in source")
    case .streamCopy: return String(localized: "Bitstream")
    case .bridged: return String(localized: "Bridged")
    case .decoded: return String(localized: "Decoded")
    case .droppedNoPipeline: return String(localized: "Dropped (no decoder)")
    case .playerManaged: return "AVFoundation"
    @unknown default: return statsPlaceholder
    }
}

func formatBackend(_ backend: PlaybackBackend) -> String {
    switch backend {
    case .native: return String(localized: "Native (AVPlayer)")
    case .software: return String(localized: "Software")
    case .audio: return String(localized: "Audio")
    case .aether: return "Aether"
    case .none: return statsPlaceholder
    @unknown default: return statsPlaceholder
    }
}
