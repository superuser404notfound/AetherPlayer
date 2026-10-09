import SwiftUI
import AetherEngine

/// The app's playback settings, shared by the macOS Preferences window (Cmd-,) and the iOS settings
/// sheet. One view rather than two, because every setting here is read in `PlayerViewModel.load` on
/// both platforms: a settings screen that existed on one of them left the other's values reachable
/// only by editing defaults by hand.
///
/// The playback settings apply to the next file opened, not to what is playing. That is a property of
/// where they are read (`LoadOptions`, once per session) rather than a simplification, so each one
/// says so. The subtitle appearance is the exception: the overlay reads it on every frame.
struct PlaybackSettingsView: View {

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    // The mode's raw value; see AudioBridgeSetting for why the stored form is the engine's spelling.
    @AppStorage(AudioBridgeSetting.defaultsKey) private var audioBridgeMode = AudioBridgeSetting.defaultMode.rawValue
    // 0 == Auto (engine default); otherwise a forward-buffer segment count
    // (AetherEngine #102, engine clamps to 4...150).
    @AppStorage("playback.forwardBufferSegments") private var forwardBufferSegments = 0
    // AetherEngine AE#455. macOS only, see where it is shown below.
    #if os(macOS)
    @AppStorage("playback.forceDolbyVisionOnNonDVDisplay") private var forceDolbyVision = false
    #endif

    @AppStorage(SubtitleAppearanceKey.size) private var subtitleSize = SubtitleSize.normal
    @AppStorage(SubtitleAppearanceKey.font) private var subtitleFont = SubtitleFont.system
    @AppStorage(SubtitleAppearanceKey.weight) private var subtitleWeight = SubtitleWeight.regular
    @AppStorage(SubtitleAppearanceKey.color) private var subtitleColor = SubtitleTextColor.white
    @AppStorage(SubtitleAppearanceKey.background) private var subtitleBackground = SubtitleBackground.box
    @AppStorage(SubtitleAppearanceKey.position) private var subtitlePosition = SubtitlePosition.standard
    @AppStorage(SubtitleAppearanceKey.embeddedStyles) private var embeddedASSStyles = true

    private var selectedMode: AudioBridgeMode { AudioBridgeSetting.resolve(stored: audioBridgeMode) }

    var body: some View {
        #if os(macOS)
        Form { sections }
            .padding(20)
            .frame(width: 460)
        #else
        NavigationStack {
            Form { sections }
                .navigationTitle("Playback")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var sections: some View {
        Picker("Multichannel audio", selection: $audioBridgeMode) {
            ForEach(AudioBridgeMode.allCases, id: \.rawValue) { mode in
                Text(AudioBridgeSetting.label(mode)).tag(mode.rawValue)
            }
        }
        caption(
            AudioBridgeSetting.explanation(selectedMode) + " "
            + String(localized: "Applies to formats that have to be re-encoded, such as TrueHD and DTS, and to the next file you open.")
        )

        divider()

        Picker("Forward buffer", selection: $forwardBufferSegments) {
            Text("Auto").tag(0)
            Text("Small (8 segments)").tag(8)
            Text("Default (30 segments)").tag(30)
            Text("Large (60 segments)").tag(60)
            Text("Maximum (120 segments)").tag(120)
        }
        caption(String(localized: "How far ahead to buffer. Higher values help slow or unstable sources at the cost of memory, and apply to the next file you open."))

        // macOS only, and not for tidiness: the switch exists because no Mac reports a Dolby Vision
        // display, so the engine serves a Profile 8.1 source as its HDR10 base layer and the RPU is
        // dropped. Every iPhone and iPad this app runs on does report one, so there is nothing for
        // the override to take over; offering it there would be a control that cannot do anything.
        #if os(macOS)
        divider()

        Toggle("Compose Dolby Vision on this display", isOn: $forceDolbyVision)
        caption(String(localized: "Experimental. No Mac reports a Dolby Vision display, so a Profile 8.1 source plays as its HDR10 base layer and the per-frame metadata is discarded. This hands the composition to AVPlayer instead. On a display without the headroom for it, expect a shifted or washed-out picture; turn it back off and reopen the file. Applies to the next file you open."))
        #endif

        divider()

        subtitleSection
    }

    @ViewBuilder
    private var subtitleSection: some View {
        Section("Subtitles") {
            Picker("Size", selection: $subtitleSize) {
                ForEach(SubtitleSize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $subtitleFont) {
                ForEach(SubtitleFont.allCases) { Text($0.label).tag($0) }
            }
            Picker("Weight", selection: $subtitleWeight) {
                ForEach(SubtitleWeight.allCases) { Text($0.label).tag($0) }
            }
            Picker("Color", selection: $subtitleColor) {
                ForEach(SubtitleTextColor.allCases) { Text($0.label).tag($0) }
            }
            Picker("Background", selection: $subtitleBackground) {
                ForEach(SubtitleBackground.allCases) { Text($0.label).tag($0) }
            }
            Picker("Position", selection: $subtitlePosition) {
                ForEach(SubtitlePosition.allCases) { Text($0.label).tag($0) }
            }
            caption(String(localized: "Applies to text subtitles such as SRT right away. High Legibility uses the Atkinson Hyperlegible typeface. Position also moves bitmap subtitles (PGS, DVB)."))

            Toggle("Use styles embedded in ASS/SSA subtitles", isOn: $embeddedASSStyles)
            caption(String(localized: "Draws ASS/SSA tracks with the fonts, colors and placement they ship with. Turn it off to show them as plain text in the style above."))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A rule between groups on macOS, where the Form is one flat column. iOS groups them itself.
    @ViewBuilder
    private func divider() -> some View {
        #if os(macOS)
        Divider()
        #endif
    }
}
