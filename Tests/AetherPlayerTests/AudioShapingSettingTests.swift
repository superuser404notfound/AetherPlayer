import Testing
import Foundation
import AetherEngine
@testable import AetherPlayer

/// AetherEngine#923: what the three stored values ask of the engine.
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

    @Test func everyChoiceIsLabelled() {
        for s in AudioShapingSetting.Speakers.allCases { #expect(!s.label.isEmpty) }
        for d in AudioShapingSetting.DialogueBoost.allCases { #expect(!d.label.isEmpty) }
    }
}
