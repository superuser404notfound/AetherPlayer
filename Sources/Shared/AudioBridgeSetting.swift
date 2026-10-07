import Foundation
import AetherEngine

/// Host policy for the audio bridge's encoder (`LoadOptions.audioBridgeMode`).
///
/// Codecs that fMP4 cannot carry (TrueHD, DTS and DTS-HD MA, MP2, WMA, raw PCM) are decoded and
/// re-encoded on the way to AVPlayer, and the encoder that happens on decides what the far end of
/// the cable can do with the result. There is no right answer for both ends at once, which is why
/// this is a setting rather than a rule:
///
/// - `.surroundCompat` re-encodes a surround source to E-AC-3, which an AVR or a soundbar takes as
///   a bitstream and decodes into its own mix. It works on essentially every sink, at 128 kbps per
///   channel, and FFmpeg's E-AC-3 encoder stops at six channels, so 7.1 is folded to 5.1.
/// - `.lossless` re-encodes to FLAC, which AVPlayer decodes to multichannel LPCM. Bit-perfect, 7.1
///   stays 7.1, and a sample rate the encoder accepts is kept untouched (AE#548), but a sink that
///   can only pass a Dolby bitstream through rather than decode one downmixes the LPCM to stereo.
///
/// Neither mode carries Atmos objects: FFmpeg's E-AC-3 encoder produces no JOC and FLAC has no
/// object concept. An Atmos source that stream-copies never reaches this decision in the first
/// place, so the setting cannot cost Atmos anything.
///
/// The default matches the engine's, because the majority of sinks are the bitstream kind and a
/// wrong guess there is a silent downmix rather than an error. It is read fresh on every open,
/// like the forward-buffer depth and the Dolby Vision switch, so a change applies to the next file.
enum AudioBridgeSetting {

    /// `UserDefaults` key. The value is `AudioBridgeMode.rawValue`, so the stored form is the
    /// engine's own spelling rather than a number this app would have to keep in step.
    static let defaultsKey = "playback.audioBridgeMode"

    /// What the engine does when nobody has chosen.
    static let defaultMode: AudioBridgeMode = .surroundCompat

    /// The mode a stored value names. Anything unreadable, including a value left behind by a case
    /// this app no longer knows, falls back to the default: every failure here ends in audio that
    /// is worse or absent, and none of them announce themselves, so none of them may propagate.
    static func resolve(stored: String?) -> AudioBridgeMode {
        guard let stored, let mode = AudioBridgeMode(rawValue: stored) else { return defaultMode }
        return mode
    }

    /// The mode currently in force.
    static func current(defaults: UserDefaults = .standard) -> AudioBridgeMode {
        resolve(stored: defaults.string(forKey: defaultsKey))
    }

    /// Picker row. Names the audible property first and the codec second, because the codec is the
    /// part someone reading this menu is least likely to be choosing by.
    ///
    /// Kept short enough to survive an iPhone's picker row, which truncates the middle rather than
    /// wrapping: "Surround compatibility (Dolby Digital Plus)" came back as "Surround compatib...
    /// (Dolby Digital Plus)", which loses the one word that distinguishes the two. What the mode
    /// trades away lives in `explanation` underneath, where there is room for it.
    static func label(_ mode: AudioBridgeMode) -> String {
        switch mode {
        case .surroundCompat: String(localized: "Surround (Dolby Digital Plus)")
        case .lossless:       String(localized: "Lossless (FLAC)")
        }
    }

    /// The trade-off in one sentence, shown under the picker for the selected mode.
    static func explanation(_ mode: AudioBridgeMode) -> String {
        switch mode {
        case .surroundCompat:
            String(localized: "Re-encodes surround to Dolby Digital Plus, which AV receivers and soundbars decode themselves. Works on almost any speaker setup. Lossy, and 7.1 is folded to 5.1.")
        case .lossless:
            String(localized: "Re-encodes to FLAC, which stays bit-perfect and keeps 7.1 whole. Best for headphones and built-in speakers; a receiver or soundbar that only accepts a Dolby bitstream will fall back to stereo.")
        }
    }
}
