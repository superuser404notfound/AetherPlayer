import SwiftUI
import AetherEngine

/// Bottom transport bar: touch scrubber (leading/trailing monospaced timecodes)
/// over a controls row (-10s / play-pause / +10s), with the backend badge. The
/// touch analog of macOS `TransportBar` (`Sources/macOS/Views/TransportBar.swift`),
/// dropping the volume slider, prev/next, rate menu, snapshot, shuffle/repeat and
/// hover (touch has none of those) in favor of skip buttons for the arrow-key skip
/// macOS gets for free.
struct PlayerTransportBar: View {
    let model: PlayerViewModel
    @Binding var scrubbing: Bool
    @State private var scrubFraction: Double = 0

    /// DVR window of a live session; nil on VOD (and on live before the first window publish).
    private var liveRange: ClosedRange<Double>? {
        guard model.isLive, let range = model.seekableLiveRange,
              range.upperBound > range.lowerBound else { return nil }
        return range
    }
    /// Seconds the scrubber spans: the DVR window on live, the duration on VOD.
    private var scrubSpanSeconds: Double {
        liveRange.map { $0.upperBound - $0.lowerBound } ?? model.duration
    }
    private var playbackFraction: Double {
        if let range = liveRange {
            let span = range.upperBound - range.lowerBound
            return min(max((model.currentTime - range.lowerBound) / span, 0), 1)
        }
        return model.duration > 0 ? model.currentTime / model.duration : 0
    }
    private var displayedTime: Double { scrubbing ? scrubFraction * model.duration : model.currentTime }
    /// Live: offset behind the live edge ("-1:23"), empty at the edge. VOD: the position.
    private var leadingLabel: String {
        guard model.isLive else { return formatTimecode(displayedTime) }
        let behind: Double
        if scrubbing, let range = liveRange {
            behind = (1 - scrubFraction) * (range.upperBound - range.lowerBound)
        } else {
            behind = model.behindLiveSeconds
        }
        return behind > 1 ? "-" + formatTimecode(behind) : ""
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(leadingLabel)
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.white)
                PlayerScrubBar(progress: playbackFraction, duration: scrubSpanSeconds,
                               scrubPreview: model.scrubPreview, scrubbing: $scrubbing,
                               scrubFraction: $scrubFraction,
                               onSeek: { model.seek(to: (liveRange?.lowerBound ?? 0) + $0) })
                if model.isLive {
                    Button { model.seekToLiveEdge() } label: {
                        HStack(spacing: 5) {
                            Circle().fill(model.isAtLiveEdge ? Color.red : Color.gray)
                                .frame(width: 7, height: 7)
                            Text("LIVE").font(.system(.caption, design: .monospaced)).bold()
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(formatTimecode(model.duration))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.white)
                }
            }
            // Rate pill + backend badge on their own trailing row, so the centered skip/play group
            // below stays truly centered and never overlaps them on a narrow portrait width. Rate
            // applies to every backend, so the pill is always shown; the backend badge is conditional.
            HStack(spacing: 8) {
                if model.playlist != nil {
                    Button { model.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(model.shuffleEnabled ? Color.aetherPurple : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                Menu {
                    ForEach(PlaybackSpeed.rates, id: \.self) { r in
                        Button { model.setRate(r) } label: {
                            Text((model.rate == r ? "\u{2713} " : "") + rateLabel(r))
                        }
                    }
                } label: {
                    Text(rateLabel(model.rate))
                        .font(.system(.caption2, design: .monospaced))
                        .aetherBadge()
                }
                .menuIndicator(.hidden)

                if !backendBadge.isEmpty {
                    Text(backendBadge).font(.system(.caption2, design: .monospaced)).aetherBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: model.playlist != nil ? 24 : 40) {
                if model.playlist != nil {
                    skipButton(system: "backward.end.fill") { Task { await model.playPrevious() } }
                        .disabled(!model.hasPrevious)
                        .opacity(model.hasPrevious ? 1 : 0.35)
                }
                skipButton(system: "gobackward.10") { model.seek(by: -10) }
                Button(action: { model.primaryAction() }) {
                    Image(systemName: playButtonSymbol).font(.system(size: 34))
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .shadow(color: .aetherPurple.opacity(0.6), radius: 6)
                skipButton(system: "goforward.10") { model.seek(by: 10) }
                if model.playlist != nil {
                    skipButton(system: "forward.end.fill") { Task { await model.playNext() } }
                        .disabled(!model.hasNext)
                        .opacity(model.hasNext ? 1 : 0.35)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func skipButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: system).font(.title) }
            .buttonStyle(.plain).foregroundStyle(.white)
    }
    private var playButtonSymbol: String {
        if model.isEnded { return "arrow.counterclockwise" }
        return model.isPlaying ? "pause.fill" : "play.fill"
    }
    private var backendBadge: String {
        switch model.backend {
        case .native: return "native"; case .software: return "sw"
        case .aether: return "aether"; case .audio: return "audio"; case .none: return ""
        }
    }
}
