import SwiftUI
import AetherEngine
import CoreText

/// Observes the subtitle state in isolation so the parent `PlayerContainerView`
/// body does not depend on the ~10 Hz `subtitleTime` clock. Reading that clock
/// high in the tree made the whole container ZStack (engine surface, click /
/// mouse / key NSViews, popover) re-evaluate 10x/sec during undisturbed
/// playback. Here the 10 Hz read is confined to this small view, and gated on
/// non-empty cues: with subtitles off the body reads neither `subtitleTime` nor
/// size, so idle playback establishes no per-tick dependency at all. (issue #2)
struct SubtitleOverlay: View {
    let model: PlayerViewModel

    @AppStorage(SubtitleAppearanceKey.size) private var size = SubtitleSize.normal
    @AppStorage(SubtitleAppearanceKey.font) private var font = SubtitleFont.system
    @AppStorage(SubtitleAppearanceKey.weight) private var weight = SubtitleWeight.regular
    @AppStorage(SubtitleAppearanceKey.color) private var color = SubtitleTextColor.white
    @AppStorage(SubtitleAppearanceKey.background) private var background = SubtitleBackground.box
    @AppStorage(SubtitleAppearanceKey.position) private var position = SubtitlePosition.standard

    var body: some View {
        if let renderer = model.assRenderer {
            // libass scales the script's PlayResX/Y onto its canvas per axis, so the canvas has to be
            // the picture, not the window: a 16:9 film on an ultrawide window stretched every glyph
            // wide and pinned the lines to the window edges instead of the picture (#9).
            GeometryReader { geo in
                let rect = SubtitleOverlayView.aspectFitRect(videoSize: model.videoSize, in: geo.size)
                ASSRenderedSubtitles(renderer: renderer,
                                     reloadSignal: model.assReloadSignal,
                                     currentOffset: model.subtitleTime)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .allowsHitTesting(false)
        } else {
            let cues = model.subtitleCues
            if cues.isEmpty {
                Color.clear
            } else {
                SubtitleOverlayView(cues: cues,
                                    subtitleTime: model.subtitleTime,
                                    style: SubtitleTextStyle(size: size, font: font, weight: weight,
                                                             color: color, background: background,
                                                             position: position),
                                    videoSize: model.videoSize,
                                    stripASSMarkup: isASSFallback)
            }
        }
    }
    private var isASSFallback: Bool {
        (model.activeSubtitleCodec == "ass" || model.activeSubtitleCodec == "ssa") && model.assRenderer == nil
    }
}

/// The user's appearance choices for text cues, bundled so the overlay takes one value.
struct SubtitleTextStyle {
    var size: SubtitleSize = .normal
    var font: SubtitleFont = .system
    var weight: SubtitleWeight = .regular
    var color: SubtitleTextColor = .white
    var background: SubtitleBackground = .box
    var position: SubtitlePosition = .standard
}

/// Renders subtitle cues active at the current playback time on top of
/// the video. Text cues: styled per `SubtitleTextStyle`, bottom-anchored.
/// Image cues (PGS / DVB): bitmap positioned by its normalized rect.
struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    /// Source-PTS clock (engine.sourceTime), the axis cue start/end times live on. NOT currentTime,
    /// which is shifted by the disc clip-0 STC origin and would offset cues on Blu-ray. (#112)
    let subtitleTime: Double
    var style = SubtitleTextStyle()
    /// Coded video size, for aspect-fitting bitmap (PGS/DVB) cues into the letterboxed video rect.
    var videoSize: CGSize = .zero
    /// True when an ASS track is active but the styled renderer bailed: text cues are raw event lines.
    var stripASSMarkup: Bool = false

    private var activeCues: [SubtitleCue] {
        cues.filter { subtitleTime >= $0.startTime && subtitleTime <= $0.endTime }
    }

    var body: some View {
        GeometryReader { geo in
            let active = activeCues
            Color.clear.overlay(alignment: .topLeading) {
                ForEach(active, id: \.id) { cue in
                    if case .image(let image) = cue.body { imageCue(image, in: geo.size) }
                }
                // Cues showing at the same time share one stack: placed one by one they all landed
                // on the same baseline and drew over each other (a sign and a dialogue line).
                placed(VStack(spacing: 6) {
                    ForEach(active, id: \.id) { cue in textCue(cue, in: geo.size) }
                }, in: geo.size)
            }
        }
    }

    // MARK: Text

    @ViewBuilder
    private func textCue(_ cue: SubtitleCue, in size: CGSize) -> some View {
        switch cue.body {
        case .text(let text):
            let shown = stripASSMarkup ? Self.strippedASSText(text) : text
            if !shown.isEmpty { styled(Text(shown), outline: Text(shown), in: size) }
        case .richText(let runs):
            styled(Text(attributed(runs, in: size)),
                   outline: Text(attributed(runs, in: size, forcedColor: .black)),
                   in: size)
        case .image:
            EmptyView()
        }
    }

    private func pointSize(in size: CGSize) -> CGFloat {
        subtitleFontSize(surfaceHeight: size.height, userScale: style.size.scale)
    }

    private func baseFont(in size: CGSize) -> Font {
        SubtitleFonts.font(style.font, weight: style.weight, size: pointSize(in: size))
    }

    private var foreground: Color {
        switch style.color {
        case .white: return .white
        case .yellow: return Color(red: 1.0, green: 0.86, blue: 0.0)
        case .gray: return Color(white: 0.85)
        }
    }

    private static func color(_ c: SubtitleColor) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Coloured runs (teletext, styled SRT) keep the source's colour and emphasis on top of the
    /// user's font; uncoloured runs take the user's colour. `forcedColor` paints the outline copies.
    private func attributed(_ runs: [SubtitleTextRun], in size: CGSize,
                            forcedColor: Color? = nil) -> AttributedString {
        let font = baseFont(in: size)
        return runs.reduce(into: AttributedString()) { acc, run in
            var piece = AttributedString(run.text)
            var runFont = font
            if run.isBold { runFont = runFont.bold() }
            if run.isItalic { runFont = runFont.italic() }
            piece.font = runFont
            piece.foregroundColor = forcedColor ?? run.color.map(Self.color) ?? foreground
            if run.isUnderlined { piece.underlineStyle = .single }
            if run.isStruckThrough { piece.strikethroughStyle = .single }
            acc.append(piece)
        }
    }

    /// `text` in the user's font, colour and background. `outline` is the same text in black,
    /// drawn eight times around it for `.outline`, since SwiftUI has no glyph stroke.
    @ViewBuilder
    private func styled(_ text: Text, outline: Text, in size: CGSize) -> some View {
        let font = baseFont(in: size)
        let body = text.font(font).foregroundStyle(foreground).multilineTextAlignment(.center)
        switch style.background {
        case .box:
            body
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        case .outline:
            let width = subtitleOutlineWidth(pointSize: pointSize(in: size))
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4
                    outline.font(font).foregroundStyle(.black).multilineTextAlignment(.center)
                        .offset(x: width * cos(angle), y: width * sin(angle))
                }
                body
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        case .shadow:
            body
                .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
                .padding(.horizontal, 12).padding(.vertical, 6)
        case .none:
            body.padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private func placed(_ content: some View, in size: CGSize) -> some View {
        // The inset goes inside the full-size frame: applied after it, it only grew the frame past
        // the bottom edge, and the line sat flush with the window whatever the setting said.
        content
            .frame(maxWidth: max(0, size.width - 160))
            .padding(.bottom, subtitleBottomInset(position: style.position, surfaceHeight: size.height))
            .frame(width: size.width, height: size.height, alignment: .bottom)
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
                                        videoSize: videoSize, in: size,
                                        verticalShift: subtitleBitmapShift(position: style.position,
                                                                           surfaceHeight: size.height))
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
                                           videoSize: CGSize, in bounds: CGSize,
                                           verticalShift: CGFloat = 0) -> CGRect {
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
        let frame = CGRect(x: canvasRect.minX + position.minX * canvasRect.width,
                           y: canvasRect.minY + position.minY * canvasRect.height + verticalShift,
                           width: position.width * canvasRect.width,
                           height: position.height * canvasRect.height)
        guard verticalShift != 0 else { return frame }
        return frame.offsetBy(dx: 0, dy: verticalClamp(frame, in: bounds))
    }

    /// Vertical delta that pulls a cue the position setting lifted back inside the bounds; a line
    /// raised past the top would read as a missing subtitle. Top wins for a cue taller than the bounds.
    nonisolated static func verticalClamp(_ frame: CGRect, in bounds: CGSize) -> CGFloat {
        guard bounds.height > 0 else { return 0 }
        var dy: CGFloat = 0
        if frame.maxY > bounds.height { dy = bounds.height - frame.maxY }
        if frame.minY + dy < 0 { dy = -frame.minY }
        return dy
    }

    /// Aspect-fit rect of the video plane within the overlay bounds. Full bounds when the video
    /// dimensions are unknown (pre-load or older cues).
    nonisolated static func aspectFitRect(videoSize: CGSize, in bounds: CGSize) -> CGRect {
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

/// Fonts for text cues. Atkinson Hyperlegible ships in the bundle and is registered for the
/// process on first use, which covers both apps without an Info.plist font list per platform.
enum SubtitleFonts {
    private static let registered: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        let faces = urls.filter { $0.lastPathComponent.hasPrefix("AtkinsonHyperlegible-") }
        for url in faces { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }()

    static func font(_ font: SubtitleFont, weight: SubtitleWeight, size: CGFloat) -> Font {
        switch font {
        case .system:
            return .system(size: size, weight: weight == .bold ? .bold : .medium)
        case .highLegibility:
            _ = registered
            return .custom(weight == .bold ? "AtkinsonHyperlegible-Bold" : "AtkinsonHyperlegible-Regular",
                           size: size)
        }
    }
}
