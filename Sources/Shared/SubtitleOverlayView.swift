import SwiftUI
import AetherEngine

/// Observes the subtitle state in isolation so the parent `PlayerContainerView`
/// body does not depend on the ~10 Hz `subtitleTime` clock. Reading that clock
/// high in the tree made the whole container ZStack (engine surface, click /
/// mouse / key NSViews, popover) re-evaluate 10x/sec during undisturbed
/// playback. Here the 10 Hz read is confined to this small view, and gated on
/// non-empty cues: with subtitles off the body reads neither `subtitleTime` nor
/// size, so idle playback establishes no per-tick dependency at all. (issue #2)
struct SubtitleOverlay: View {
    let model: PlayerViewModel

    var body: some View {
        if let renderer = model.assRenderer {
            ASSRenderedSubtitles(renderer: renderer,
                                 reloadSignal: model.assReloadSignal,
                                 currentOffset: model.subtitleTime)
                .allowsHitTesting(false)
        } else {
            let cues = model.subtitleCues
            if cues.isEmpty {
                Color.clear
            } else {
                SubtitleOverlayView(cues: cues,
                                    subtitleTime: model.subtitleTime,
                                    userScale: model.subtitleSize.scale,
                                    videoSize: model.videoSize,
                                    stripASSMarkup: isASSFallback)
            }
        }
    }
    private var isASSFallback: Bool {
        (model.activeSubtitleCodec == "ass" || model.activeSubtitleCodec == "ssa") && model.assRenderer == nil
    }
}

/// Renders subtitle cues active at the current playback time on top of
/// the video. Text cues: centered semi-transparent box near the bottom.
/// Image cues (PGS / DVB): bitmap positioned by its normalized rect.
struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    /// Source-PTS clock (engine.sourceTime), the axis cue start/end times live on. NOT currentTime,
    /// which is shifted by the disc clip-0 STC origin and would offset cues on Blu-ray. (#112)
    let subtitleTime: Double
    /// User size multiplier (from PlayerViewModel.subtitleSize.scale).
    var userScale: CGFloat = 1.0
    /// Coded video size, for aspect-fitting bitmap (PGS/DVB) cues into the letterboxed video rect.
    var videoSize: CGSize = .zero
    /// True when an ASS track is active but the styled renderer bailed: text cues are raw event lines.
    var stripASSMarkup: Bool = false

    private var activeCues: [SubtitleCue] {
        cues.filter { subtitleTime >= $0.startTime && subtitleTime <= $0.endTime }
    }

    var body: some View {
        GeometryReader { geo in
            Color.clear.overlay(alignment: .topLeading) {
                ForEach(activeCues, id: \.id) { cue in
                    switch cue.body {
                    case .text(let text):
                        textCue(text, in: geo.size)
                    case .richText(let runs):
                        richCue(runs, in: geo.size)
                    case .image(let image):
                        imageCue(image, in: geo.size)
                    }
                }
            }
        }
    }

    private func textCue(_ text: String, in size: CGSize) -> some View {
        let shown = stripASSMarkup ? Self.strippedASSText(text) : text
        return Text(shown)
            .font(.system(size: subtitleFontSize(surfaceHeight: size.height, userScale: userScale),
                          weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: max(0, size.width - 160))
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .padding(.bottom, 48)
    }

    private static func color(_ c: SubtitleColor) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    private func richCue(_ runs: [SubtitleTextRun], in size: CGSize) -> some View {
        let font = Font.system(size: subtitleFontSize(surfaceHeight: size.height, userScale: userScale), weight: .medium)
        let colored = runs.reduce(Text(verbatim: "")) { acc, run in
            acc + Text(run.text).font(font).foregroundColor(run.color.map(Self.color) ?? .white)
        }
        return colored
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: max(0, size.width - 160))
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .padding(.bottom, 48)
    }

    /// Fallback when the styled renderer is unavailable: raw event lines
    /// must never reach the screen. Mirrors the engine's cleanASSBody.
    static func strippedASSText(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.split(separator: "\n") {
            // ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text
            // Integer ReadOrder gate so clean sidecar text with 8+ commas isn't truncated.
            let fields = line.split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
            guard fields.count == 9, Int(fields[0]) != nil else { lines.append(String(line)); continue }
            var text = String(fields[8])
            text = text.replacingOccurrences(of: "\\N", with: "\n")
            text = text.replacingOccurrences(of: "\\n", with: "\n")
            text = text.replacingOccurrences(of: "\\h", with: " ")
            text = text.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        return lines.joined(separator: "\n")
    }

    private func imageCue(_ image: SubtitleImage, in size: CGSize) -> some View {
        let frame = Self.bitmapCueFrame(position: image.position, canvas: image.canvasSize,
                                        videoSize: videoSize, in: size)
        return Image(decorative: image.cgImage, scale: 1.0)
            .resizable()
            .interpolation(.high)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    /// Screen frame for one bitmap cue. Positions are normalized to the subtitle composition
    /// canvas (often 16:9 even when the video is scope-cropped), so the canvas maps onto the
    /// aspect-fit video rect, center-anchored, and cues land where they were authored, including
    /// the letterbox bar, instead of stretching to the full overlay bounds.
    nonisolated static func bitmapCueFrame(position: CGRect, canvas: CGSize,
                                           videoSize: CGSize, in bounds: CGSize) -> CGRect {
        let videoRect = aspectFitRect(videoSize: videoSize, in: bounds)
        let canvasRect: CGRect
        if videoRect.width > 0, canvas.width > 0, canvas.height > 0, videoSize.width > 0 {
            // Scale the canvas so it COVERS the video rect: the video is a crop of the plane
            // (scope cropped out of a 16:9 canvas) or a rescale of it, and either way its picture
            // fills the canvas. Scaling by coded video pixels instead assumed canvas and video
            // share a pixel grid, which a downscaled encode breaks: a 720p rip carrying the disc's
            // 1920x1080 PGS plane blew the canvas up 1.5x, so lines rendered 1.5x too wide and ran
            // off the bottom edge of the screen.
            let scale = max(videoRect.width / canvas.width, videoRect.height / canvas.height)
            let w = canvas.width * scale
            let h = canvas.height * scale
            canvasRect = CGRect(x: videoRect.midX - w / 2, y: videoRect.midY - h / 2, width: w, height: h)
        } else {
            // Unknown dims (pre-load or an older cue): the historical full-bounds layout.
            canvasRect = CGRect(origin: .zero, size: bounds)
        }
        return CGRect(x: canvasRect.minX + position.minX * canvasRect.width,
                      y: canvasRect.minY + position.minY * canvasRect.height,
                      width: position.width * canvasRect.width,
                      height: position.height * canvasRect.height)
    }

    /// Aspect-fit rect of the video plane within the overlay bounds. Full bounds when the video
    /// dimensions are unknown (pre-load or older cues).
    nonisolated private static func aspectFitRect(videoSize: CGSize, in bounds: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let videoAspect = videoSize.width / videoSize.height
        let boundsAspect = bounds.width / bounds.height
        if boundsAspect > videoAspect {
            let w = bounds.height * videoAspect
            return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
        } else {
            let h = bounds.width / videoAspect
            return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        }
    }
}
