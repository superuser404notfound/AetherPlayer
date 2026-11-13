import Testing
import AetherEngine
@testable import AetherPlayer

/// AetherEngine#846, #1039: the two stored switches and what the engine is asked for.
struct UpscalingSettingTests {

    @Test func theTwoSwitchesFoldIntoOneChoice() {
        #expect(UpscalingSetting(enabled: false, lineArt: true) == .off)
        #expect(UpscalingSetting(enabled: true, lineArt: false) == .on)
        #expect(UpscalingSetting(enabled: true, lineArt: true) == .lineArt)
    }

    @Test func eachChoiceAsksForItsScaler() {
        #expect(!UpscalingSetting.off.upscales)
        #expect(UpscalingSetting.on.upscales && UpscalingSetting.on.scaler == .automatic)
        #expect(UpscalingSetting.lineArt.upscales && UpscalingSetting.lineArt.scaler == .lineArt)
    }
}
