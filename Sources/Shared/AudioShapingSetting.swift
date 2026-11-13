import Foundation
import AetherEngine

/// Host policy for the engine's audio shaping (`LoadOptions.audioShaping`, `setAudioShaping`,
/// AetherEngine#923): a channel cap, a dialogue lift, night-mode compression, a loudness target for
/// quiet sources (#1036) and the LFE in a stereo fold (#1044).
///
/// Like the lip-sync offset these describe the room and the speakers, not the file, so they are
/// persisted, handed to every `load`, and a change goes to the running session as well. The
/// values live in `UserDefaults` so the settings window, the macOS Audio menu and the iOS tracks
/// sheet can bind them directly; `PlayerViewModel` follows the defaults and forwards a change.
///
/// While any of them is on the engine has to decode the audio to shape it, so a stream-copied track
/// is bridged instead and Atmos plays as its bed. Off, everything plays as before.
enum AudioShapingSetting {

    static let speakersKey = "playback.speakerLayout"
    static let dialogueKey = "playback.dialogueBoost"
    static let nightModeKey = "playback.nightMode"
    static let loudnessKey = "playback.loudnessTarget"
    static let lfeInStereoKey = "playback.lfeInStereoDownmix"

    /// How many channels go to the output at most. Auto leaves it to the route.
    enum Speakers: String, CaseIterable, Identifiable {
        case auto, stereo, surround51
        var id: String { rawValue }

        var maxChannels: Int? {
            switch self {
            case .auto: nil
            case .stereo: 2
            case .surround51: 6
            }
        }

        var label: String {
            switch self {
            case .auto: String(localized: "Auto")
            case .stereo: String(localized: "Stereo")
            case .surround51: String(localized: "5.1 Surround")
            }
        }
    }

    /// How far the dialogue is lifted against the rest of the mix: the centre channel of a surround
    /// source, or on a stereo source the dialogue FFmpeg's `dialoguenhance` finds in the pair.
    enum DialogueBoost: String, CaseIterable, Identifiable {
        case off, low, medium, high
        var id: String { rawValue }

        var gainDB: Double {
            switch self {
            case .off: 0
            case .low: 3
            case .medium: 6
            case .high: 9
            }
        }

        var label: String {
            switch self {
            case .off: String(localized: "Off")
            case .low: String(localized: "Low")
            case .medium: String(localized: "Medium")
            case .high: String(localized: "High")
            }
        }
    }

    /// How far a quiet source is raised (AE#1036). The engine measures what it has played and only
    /// ever lifts, over seconds, so a file mastered at or above the target plays as it was.
    enum Loudness: String, CaseIterable, Identifiable {
        case off, gentle, strong
        var id: String { rawValue }

        /// -24 LUFS is broadcast loudness, -16 roughly where streaming services sit.
        var targetLUFS: Double? {
            switch self {
            case .off: nil
            case .gentle: -24
            case .strong: -16
            }
        }

        var label: String {
            switch self {
            case .off: String(localized: "Off")
            case .gentle: String(localized: "Gentle")
            case .strong: String(localized: "Strong")
            }
        }
    }

    /// What the stored values ask of the engine. An unreadable value falls back to off, which plays
    /// the audio exactly as it would without this feature.
    static func resolve(speakers: String?, dialogue: String?, nightMode: Bool,
                        loudness: String? = nil, lfeInStereo: Bool = false) -> AudioShaping {
        let cap = speakers.flatMap(Speakers.init(rawValue:))?.maxChannels
        return AudioShaping(maxChannels: cap,
                            dialogueGainDB: dialogue.flatMap(DialogueBoost.init(rawValue:))?.gainDB ?? 0,
                            compressor: nightMode ? .night : nil,
                            loudnessTargetLUFS: loudness.flatMap(Loudness.init(rawValue:))?.targetLUFS,
                            // Only the stereo cap folds here (Auto leaves the fold to the system, which
                            // drops the LFE on its own). 0 dB is libswresample's lfe_mix_level, so each
                            // side gets the LFE 3 dB down.
                            lfeMixDB: lfeInStereo && cap == 2 ? 0 : nil)
    }

    static func current(defaults: UserDefaults = .standard) -> AudioShaping {
        resolve(speakers: defaults.string(forKey: speakersKey),
                dialogue: defaults.string(forKey: dialogueKey),
                nightMode: defaults.bool(forKey: nightModeKey),
                loudness: defaults.string(forKey: loudnessKey),
                lfeInStereo: defaults.bool(forKey: lfeInStereoKey))
    }

    static var explanation: String {
        String(localized: "Speakers caps the channels sent to the output, dialogue boost raises speech against music and effects, and night mode narrows the gap between quiet and loud scenes. Applies right away. While any of them is on, Atmos plays without its height channels.")
    }

    static var loudnessExplanation: String {
        String(localized: "Raise quiet sources lifts a file mastered too quietly to a steady level, adjusting over a few seconds. It never turns anything down.")
    }

    static var lfeExplanation: String {
        String(localized: "Mixes the .1 bass channel into left and right instead of dropping it. For a 2.1 system whose subwoofer hangs off a stereo amp or streamer.")
    }
}
