import SwiftUI
import AetherEngine

/// Live playback statistics, QuickTime-Inspector style. Observes the engine's
/// dedicated diagnostics object (1 Hz) so per-second telemetry does not churn
/// views bound to the engine itself, plus the @Observable PlayerViewModel.
struct StatsInspectorView: View {
    let model: PlayerViewModel
    @ObservedObject private var diagnostics: EngineDiagnostics

    init(model: PlayerViewModel) {
        self.model = model
        _diagnostics = ObservedObject(wrappedValue: model.engine.diagnostics)
    }

    /// The engine's TrackInfo for the playing audio track (channels + Atmos + declared bitrate). nil during the
    /// brief session-start window before the engine resolves one, or for video-only sources.
    private var activeAudioTrack: TrackInfo? {
        model.audioTracks.first { $0.id == model.activeAudioTrackIndex }
    }

    /// AE#658: the engine decoder's own output where it decodes (software path), the source's declaration
    /// otherwise. On the native path AVPlayer decodes and the frames never reach the engine.
    private var videoStreamFormat: VideoStreamFormat? {
        model.engine.decodedVideoFormat?.frame ?? model.engine.sourceVideoStreamFormat
    }

    var body: some View {
        let tele = diagnostics.liveTelemetry
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Source") {
                    row("File", model.loadedURL?.lastPathComponent ?? "\u{2012}")
                    row("Duration", formatTimecode(model.duration))
                    row("Live", model.engine.isLive ? String(localized: "Yes") : String(localized: "No"))
                }
                section("Video") {
                    row("Codec", formatCodec(model.engine.sourceVideoCodecName,
                                             profile: model.engine.sourceVideoStreamFormat?.profile))
                    row("Resolution", formatResolution(
                        width: Int(model.engine.sourceVideoWidth),
                        height: Int(model.engine.sourceVideoHeight)))
                    row("Frame rate", formatFrameRate(model.engine.sourceVideoFrameRate))
                    row("Bitrate", formatBitrateBps(model.engine.sourceVideoBitrate))
                    row("Dynamic range", dynamicRangeLabel(
                        source: model.engine.sourceVideoFormat,
                        effective: model.engine.videoFormat,
                        dvProfile: model.engine.sourceDVProfile,
                        conversion: model.engine.dolbyVisionConversion))
                    row("Pixel format", videoStreamFormat?.pixelFormat ?? "\u{2012}")
                    row("Bit depth", formatBitDepth(videoStreamFormat?.bitDepth))
                    row("Primaries", videoStreamFormat?.colorPrimariesLabel ?? "\u{2012}")
                    row("Transfer", videoStreamFormat?.transferLabel ?? "\u{2012}")
                    row("Matrix", videoStreamFormat?.matrixLabel ?? "\u{2012}")
                    row("Range", videoStreamFormat?.rangeLabel ?? "\u{2012}")
                    if let decoded = model.engine.decodedVideoFormat {
                        row("Display buffer", decoded.pixelBufferLabel)
                    }
                    row("Display mode", currentDisplayModeLabel())
                    row("Decoder", model.engine.activeVideoDecoder ?? "\u{2012}")
                    row("Backend", formatBackend(model.backend))
                }
                section("Audio") {
                    row("Decoder", model.engine.activeAudioDecoder ?? "\u{2012}")
                    if let track = activeAudioTrack {
                        row("Codec", formatCodec(track.codec, profile: track.profile))
                        row("Channels", formatChannels(track.channels, isAtmos: track.isAtmos))
                        row("Sample rate", formatSampleRate(track.sampleRate))
                        row("Bit depth", formatBitDepth(track.bitsPerSample))
                        row("Sample format", track.sampleFormat ?? "\u{2012}")
                        row("Bitrate", formatBitrateBps(track.bitrate))
                    }
                    if let bridge = tele?.audioBridgeBitrateMbps {
                        row("Bridge output", formatMbps(bridge))
                    }
                    row("Delivery", formatAudioDelivery(model.audioDelivery))
                    row("Delay", AudioDelay.label(model.audioDelaySeconds))
                    row("Tracks", "\(model.audioTracks.count)")
                }
                section("Live") {
                    row("FPS", formatFps(tele?.observedFps))
                    row("Dropped frames", formatDroppedFrames(tele?.droppedFrameCount))
                    row("Bitrate (inst)", formatMbps(tele?.instantBitrateMbps))
                    row("Bitrate (avg)", formatMbps(tele?.averageBitrateMbps))
                    row("Buffer ahead", formatSeconds(tele?.forwardBufferSeconds))
                    row("A/V sync", tele.map { formatSeconds($0.avSyncGapMs.map { $0 / 1000 }) } ?? "\u{2012}")
                    row("Memory", tele.map { formatMemoryMB($0.rssMb) } ?? "\u{2012}")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No minimum size here. macOS mounts this in a resizable window, iOS as a fixed overlay in the
        // player, and a minimum the iOS host cannot grant (iPhone landscape) overflows the whole chrome
        // off screen. The window minimum lives at the macOS call site instead.
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
