import SwiftUI
import AetherEngine

struct TransportBar: View {
    let model: PlayerViewModel
    let onTracksTapped: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    /// Bound to PlayerContainerView so the auto-hide timer can keep the
    /// controls visible while a scrub is in progress (otherwise hiding the
    /// bar mid-drag would drop the deferred seek).
    @Binding var scrubbing: Bool
    @State private var scrubFraction: Double = 0

    /// Live playback position as a 0...1 fraction.
    private var playbackFraction: Double {
        model.duration > 0 ? model.currentTime / model.duration : 0
    }
    /// Seconds shown by the leading timecode label: the scrub position while
    /// dragging, otherwise the live playback time.
    private var displayedTime: Double {
        scrubbing ? scrubFraction * model.duration : model.currentTime
    }

    var body: some View {
        VStack(spacing: 8) {
            // Scrubber
            HStack(spacing: 10) {
                Text(formatTimecode(displayedTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                ScrubBar(
                    progress: playbackFraction,
                    duration: model.duration,
                    scrubPreview: model.scrubPreview,
                    scrubbing: $scrubbing,
                    scrubFraction: $scrubFraction,
                    onSeek: { model.seek(to: $0) }
                )
                Text(formatTimecode(model.duration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
            }
            // Controls row
            HStack(spacing: 16) {
                Button(action: { model.primaryAction() }) {
                    Image(systemName: playButtonSymbol)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .shadow(color: .aetherPurple.opacity(0.6), radius: 6)

                Button(action: { onPrevious() }) {
                    Image(systemName: "backward.end.fill").font(.title3)
                }
                .buttonStyle(.plain).aetherHover().disabled(!model.hasPrevious)

                Button(action: { onNext() }) {
                    Image(systemName: "forward.end.fill").font(.title3)
                }
                .buttonStyle(.plain).aetherHover().disabled(!model.hasNext)

                HStack(spacing: 6) {
                    Button(action: { model.toggleMute() }) {
                        Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { Double(model.volume) },
                                          set: { model.volume = Float($0) }),
                           in: 0...1)
                        .frame(width: 90)
                        .tint(.aetherPurple)
                }

                Spacer()

                Text(backendBadge)
                    .font(.system(.caption2, design: .monospaced))
                    .aetherBadge()

                Menu {
                    ForEach(PlayerViewModel.availableRates, id: \.self) { r in
                        Button {
                            model.setRate(r)
                        } label: {
                            Text((model.rate == r ? "\u{2713} " : "") + rateLabel(r))
                        }
                    }
                } label: {
                    Text(rateLabel(model.rate))
                        .font(.system(.caption, design: .monospaced))
                        .aetherBadge()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                if model.backend == .audio {
                    Button(action: { model.toggleShuffle() }) {
                        Image(systemName: "shuffle").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.shuffleEnabled
                                     ? AnyShapeStyle(Color.aetherPurple)
                                     : AnyShapeStyle(.white.opacity(0.45)))
                    .help(model.shuffleEnabled ? String(localized: "Shuffle: on") : String(localized: "Shuffle: off"))

                    Button(action: { model.cycleRepeatMode() }) {
                        Image(systemName: repeatSymbol).font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.repeatMode == .off
                                     ? AnyShapeStyle(.white.opacity(0.45))
                                     : AnyShapeStyle(Color.aetherPurple))
                    .help(repeatHelp)
                }

                if model.backend != .audio {
                    Button(action: { SnapshotSaver.captureAndSave(model: model) }) {
                        Image(systemName: "camera").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .aetherHover()
                    .disabled(!model.hasMedia)
                }

                Button(action: onTracksTapped) {
                    Image(systemName: "captions.bubble").font(.title3)
                }
                .buttonStyle(.plain)
                .aetherHover()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// "1x", "1.5x", "0.5x" -- drops trailing ".0" for whole rates.
    private var playButtonSymbol: String {
        if model.isEnded { return "arrow.counterclockwise" }
        return model.isPlaying ? "pause.fill" : "play.fill"
    }

    private var backendBadge: String {
        switch model.backend {
        case .native: return "native"
        case .software: return "sw"
        case .aether: return "aether"
        case .audio: return "audio"
        case .none: return ""
        }
    }

    private var repeatSymbol: String {
        model.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatHelp: String {
        switch model.repeatMode {
        case .off: return String(localized: "Repeat: off")
        case .all: return String(localized: "Repeat: all tracks in folder")
        case .one: return String(localized: "Repeat: current track")
        }
    }
}

/// Custom scrub track: click-to-seek, drag-to-scrub, and hover-to-preview in
/// one view. A click or drag commits the seek on release (deferred), so the
/// engine isn't hammered mid-drag; hovering only drives the floating preview
/// and never moves playback. The preview bubble follows the cursor (or the
/// drag) and stays clamped within the track.
private struct ScrubBar: View {
    let progress: Double          // 0...1 live playback position
    let duration: Double
    let scrubPreview: ScrubPreviewProvider
    @Binding var scrubbing: Bool
    @Binding var scrubFraction: Double
    let onSeek: (Double) -> Void

    @State private var hovering = false
    @State private var hoverFraction: Double = 0

    private let trackHeight: CGFloat = 4
    private let previewWidth: CGFloat = 160

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let active = min(max(scrubbing ? scrubFraction : progress, 0), 1)
            let knobX = CGFloat(active) * width
            let emphasized = scrubbing || hovering
            let knobSize: CGFloat = emphasized ? 16 : 12
            let bubbleFraction = scrubbing ? scrubFraction : hoverFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(LinearGradient.aetherAccent)
                    .frame(width: knobX, height: trackHeight)
                Circle()
                    .fill(Color.aetherPurple)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: knobX - knobSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubbing = true
                        scrubFraction = fraction(forX: Double(value.location.x), width: Double(width))
                        scrubPreview.update(fraction: scrubFraction, durationSeconds: duration)
                    }
                    .onEnded { value in
                        let f = fraction(forX: Double(value.location.x), width: Double(width))
                        scrubFraction = f
                        onSeek(f * duration)
                        scrubbing = false
                        if !hovering { scrubPreview.clear() }
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if !hovering { scrubPreview.prewarm() }
                    hovering = true
                    hoverFraction = fraction(forX: Double(point.x), width: Double(width))
                    if !scrubbing {
                        scrubPreview.update(fraction: hoverFraction, durationSeconds: duration)
                    }
                case .ended:
                    hovering = false
                    if !scrubbing { scrubPreview.clear() }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if emphasized, let image = scrubPreview.previewImage {
                    ScrubThumbnail(image: image, time: bubbleFraction * duration)
                        .offset(
                            x: scrubThumbX(fraction: bubbleFraction,
                                           width: Double(width),
                                           thumbWidth: Double(previewWidth)),
                            y: -90
                        )
                }
            }
        }
        .frame(height: 22)
    }
}

/// The floating keyframe preview shown above the playhead while scrubbing.
private struct ScrubThumbnail: View {
    let image: CGImage
    let time: Double

    private static let width: CGFloat = 160

    /// Height from the frame's own aspect ratio. Fixing both dimensions keeps
    /// the thin track overlay (22 pt tall) from squashing the proposed height.
    private var height: CGFloat {
        image.width > 0 ? Self.width * CGFloat(image.height) / CGFloat(image.width)
                        : Self.width * 9 / 16
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .frame(width: Self.width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
            Text(formatTimecode(time))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.black.opacity(0.6), in: Capsule())
        }
        .shadow(radius: 6)
    }
}
