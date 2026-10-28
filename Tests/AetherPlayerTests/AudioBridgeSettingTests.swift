import Testing
import Foundation
import AetherEngine
@testable import AetherPlayer

/// The bridge-encoder choice's pure half: what a stored string resolves to, and what each mode
/// reads as on screen. The resolution is the part worth pinning, because every way it can fail
/// ends in audio that is worse or absent, with nothing on screen saying so.
struct AudioBridgeSettingTests {

    @Test func absentValueTakesTheEngineDefault() {
        #expect(AudioBridgeSetting.resolve(stored: nil) == .surroundCompat)
    }

    @Test func emptyValueTakesTheEngineDefault() {
        #expect(AudioBridgeSetting.resolve(stored: "") == .surroundCompat)
    }

    @Test func anUnknownValueTakesTheEngineDefaultRatherThanFailing() {
        // A value left behind by a renamed case must not strand playback on something unplayable.
        #expect(AudioBridgeSetting.resolve(stored: "atmosPassthrough") == .surroundCompat)
    }

    @Test func eachModeRoundTripsThroughItsStoredForm() {
        for mode in AudioBridgeMode.allCases {
            #expect(AudioBridgeSetting.resolve(stored: mode.rawValue) == mode,
                    "\(mode.rawValue) must survive a write and a read")
        }
    }

    @Test func bothModesAreOfferedAndNamed() {
        // The picker is built from allCases, so a mode the engine adds shows up without an edit
        // here; what it must never do is show up unlabelled.
        for mode in AudioBridgeMode.allCases {
            #expect(!AudioBridgeSetting.label(mode).isEmpty)
            #expect(!AudioBridgeSetting.explanation(mode).isEmpty)
        }
        #expect(AudioBridgeSetting.label(.lossless) != AudioBridgeSetting.label(.surroundCompat))
    }
}

/// AetherEngine#731, #744: TrueHD Atmos and DTS:X keep their heights unless someone turns it off.
struct TrueHDAtmosSettingTests {

    @Test func onWhenNobodyHasChosen() {
        #expect(TrueHDAtmosSetting.resolve(enabled: nil) == .render(.l916))
    }

    @Test func offFallsBackToTheBridge() {
        #expect(TrueHDAtmosSetting.resolve(enabled: false) == .off)
        #expect(TrueHDAtmosSetting.resolve(enabled: true) == .render(.l916))
    }

    @Test func trueHDAtmosIsLabelledAtmosInTheTrackMenu() {
        let atmos = TrackInfo(id: 1, name: "", codec: "truehd", language: "en", channels: 8, isDefault: true,
                              profile: "Dolby TrueHD + Dolby Atmos")
        let plain = TrackInfo(id: 2, name: "", codec: "truehd", language: "en", channels: 8, isDefault: false)
        let rows = audioMenuRows([atmos, plain], activeIndex: 1)
        #expect(rows[0].label.hasSuffix("Atmos"))
        #expect(rows[1].label.hasSuffix("7.1"))
    }

    @Test func dtsXIsLabelledInTheTrackMenu() {
        let dtsX = TrackInfo(id: 1, name: "", codec: "dts", language: "en", channels: 8, isDefault: true,
                             profile: "DTS-HD MA + DTS:X")
        let plain = TrackInfo(id: 2, name: "", codec: "dts", language: "en", channels: 8, isDefault: false,
                              profile: "DTS-HD MA")
        let rows = audioMenuRows([dtsX, plain], activeIndex: 1)
        #expect(rows[0].label.hasSuffix("DTS:X"))
        #expect(rows[1].label.hasSuffix("7.1"))
    }
}
