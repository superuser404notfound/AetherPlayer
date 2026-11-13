import Testing
import Foundation
import AetherEngine
@testable import AetherPlayer

/// AetherEngine#923, #1036, #1044: what the stored values ask of the engine.
struct AudioShapingSettingTests {

    @Test func nothingStoredIsNoShaping() {
        let shaping = AudioShapingSetting.resolve(speakers: nil, dialogue: nil, nightMode: false)
        #expect(shaping == AudioShaping())
        #expect(!shaping.isActive)
    }

    @Test func anUnknownValueIsOffRatherThanAGuess() {
        let shaping = AudioShapingSetting.resolve(speakers: "atmos714", dialogue: "max", nightMode: false)
        #expect(shaping == AudioShaping())
    }

    @Test func eachChoiceMapsToItsEngineValue() {
        #expect(AudioShapingSetting.resolve(speakers: "stereo", dialogue: nil, nightMode: false).maxChannels == 2)
        #expect(AudioShapingSetting.resolve(speakers: "surround51", dialogue: nil, nightMode: false).maxChannels == 6)
        #expect(AudioShapingSetting.resolve(speakers: "auto", dialogue: nil, nightMode: false).maxChannels == nil)
        let gains = AudioShapingSetting.DialogueBoost.allCases.map {
            AudioShapingSetting.resolve(speakers: nil, dialogue: $0.rawValue, nightMode: false).dialogueGainDB
        }
        #expect(gains == [0, 3, 6, 9])
        #expect(AudioShapingSetting.resolve(speakers: nil, dialogue: nil, nightMode: true).compressor == .night)
    }

    @Test func loudnessTargetsAndAnUnknownValue() {
        let targets = AudioShapingSetting.Loudness.allCases.map {
            AudioShapingSetting.resolve(speakers: nil, dialogue: nil, nightMode: false, loudness: $0.rawValue).loudnessTargetLUFS
        }
        #expect(targets == [nil, -24, -16])
        #expect(AudioShapingSetting.resolve(speakers: nil, dialogue: nil, nightMode: false, loudness: "max").loudnessTargetLUFS == nil)
        #expect(AudioShapingSetting.resolve(speakers: nil, dialogue: nil, nightMode: false, loudness: "gentle").isActive)
    }

    /// AE#1044: the LFE goes into the fold only where this app asks for one, the stereo cap.
    @Test func lfeOnlyRidesTheStereoCap() {
        #expect(AudioShapingSetting.resolve(speakers: "stereo", dialogue: nil, nightMode: false, lfeInStereo: true).lfeMixDB == 0)
        #expect(AudioShapingSetting.resolve(speakers: "stereo", dialogue: nil, nightMode: false, lfeInStereo: false).lfeMixDB == nil)
        #expect(AudioShapingSetting.resolve(speakers: "auto", dialogue: nil, nightMode: false, lfeInStereo: true).lfeMixDB == nil)
        #expect(AudioShapingSetting.resolve(speakers: "surround51", dialogue: nil, nightMode: false, lfeInStereo: true).lfeMixDB == nil)
    }

    @Test func everyChoiceIsLabelled() {
        for s in AudioShapingSetting.Speakers.allCases { #expect(!s.label.isEmpty) }
        for d in AudioShapingSetting.DialogueBoost.allCases { #expect(!d.label.isEmpty) }
        for l in AudioShapingSetting.Loudness.allCases { #expect(!l.label.isEmpty) }
        for u in UpscalingSetting.allCases { #expect(!u.label.isEmpty) }
    }
}
