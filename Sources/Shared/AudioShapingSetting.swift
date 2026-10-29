import Foundation
import AetherEngine

/// Host policy for the engine's audio shaping (`LoadOptions.audioShaping`, `setAudioShaping`,
/// AetherEngine#923): a channel cap, a dialogue lift and night-mode compression.
///
/// Like the lip-sync offset these describe the room and the speakers, not the file, so they are
/// persisted, handed to every `load`, and a change goes to the running session as well. The three
/// values live in `UserDefaults` so the settings window, the macOS Audio menu and the iOS tracks
/// sheet can bind them directly; `PlayerViewModel` follows the defaults and forwards a change.
///
/// While any of them is on the engine has to decode the audio to shape it, so a stream-copied track
/// is bridged instead and Atmos plays as its bed. Off, everything plays as before.
enum AudioShapingSetting {

    static let speakersKey = "playback.speakerLayout"
    static let dialogueKey = "playback.dialogueBoost"
    static let nightModeKey = "playback.nightMode"

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

    /// What the stored values ask of the engine. An unreadable value falls back to off, which plays
    /// the audio exactly as it would without this feature.
    static func resolve(speakers: String?, dialogue: String?, nightMode: Bool) -> AudioShaping {
        AudioShaping(maxChannels: speakers.flatMap(Speakers.init(rawValue:))?.maxChannels,
                     dialogueGainDB: dialogue.flatMap(DialogueBoost.init(rawValue:))?.gainDB ?? 0,
                     compressor: nightMode ? .night : nil)
    }

    static func current(defaults: UserDefaults = .standard) -> AudioShaping {
        resolve(speakers: defaults.string(forKey: speakersKey),
                dialogue: defaults.string(forKey: dialogueKey),
                nightMode: defaults.bool(forKey: nightModeKey))
    }

    static var explanation: String {
        String(localized: "Speakers caps the channels sent to the output, dialogue boost raises speech against music and effects, and night mode narrows the gap between quiet and loud scenes. Applies right away. While any of them is on, Atmos plays without its height channels.")
    }
}
