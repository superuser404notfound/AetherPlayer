import CoreGraphics
import Foundation
import AetherEngine

/// Sodalite#118, ported: Fill zooms past black bars painted into the frame. The area comes from a
/// hand-picked ratio or from AetherEngine's `PictureAreaScanner`, which samples keyframes once the
/// file plays and keeps reading ahead of the playhead, so a wider passage (IMAX) widens the area
/// before it is on screen.
extension PlayerViewModel {
    static let pictureAreaLookAheadInterval: Duration = .seconds(10)

    var activePictureChoice: PictureChoice { pictureIsFill ? .fill(fillRatio) : .original }

    /// The part of the picture that should cover the window, nil for Original, for audio, and while
    /// the picture is not shown here (PiP, AirPlay).
    var effectivePictureArea: CGRect? {
        guard !pictureZoomSuppressed, !isAudioOnly else { return nil }
        let size = videoSize
        let aspect = size.width > 0 && size.height > 0 ? Double(size.width / size.height) : 16.0 / 9.0
        return activePictureChoice.area(presentationAspect: aspect, detected: detectedPictureArea)
    }

    func selectPictureChoice(_ choice: PictureChoice) {
        if case .fill(let ratio) = choice {
            pictureIsFill = true
            fillRatio = ratio
        } else {
            pictureIsFill = false
        }
        applyPicture(animated: true)
        startPictureAreaScanIfNeeded()
    }

    func isPictureChoiceEnabled(_ choice: PictureChoice) -> Bool {
        PictureChoice.isEnabled(choice, presentationSize: videoSize, surface: pictureSurfaceSize,
                                detected: detectedPictureArea, scanState: pictureAreaScanState)
    }

    func pictureChoiceTitle(_ choice: PictureChoice) -> String { choice.title(detected: detectedPictureArea) }

    /// Fill is aspect-fit plus a zoom. The engine zooms its own surface (the Mac, the software path on
    /// iOS); `onPictureGeometryChanged` lets the iOS host zoom AVKit's layer for the native path.
    func applyPicture(animated: Bool = false) {
        engine.videoGravity = .resizeAspect
        let area = effectivePictureArea
        engine.setFillPictureArea(area, animated: animated)
        onPictureGeometryChanged?(area, animated)
    }

    nonisolated static func shouldScanPictureArea(choice: PictureChoice, isPlaying: Bool, isLive: Bool, isAudioOnly: Bool) -> Bool {
        choice == .fill(.auto) && isPlaying && !isLive && !isAudioOnly
    }

    private var pictureAreaCacheKey: String? {
        loadedURL.map { PictureAreaCache.key(url: $0, discTitleID: engine.selectedDiscTitle?.id) }
    }

    /// Before an open (`seedFromSettings`), at a title switch and at stop.
    func resetPicture(seedFromSettings: Bool) {
        pictureGeneration += 1
        stopPictureAreaScan()
        detectedPictureArea = nil
        pictureAreaScanState = .idle
        if seedFromSettings {
            pictureIsFill = PictureSizeSetting.stored == .fill
            fillRatio = .auto
        }
        // The engine keeps its fill area across loads; the next file must not open with this zoom.
        applyPicture()
    }

    /// After a load: a cached area applies right away, before the scan would find it again.
    func preparePicture() {
        if let key = pictureAreaCacheKey, let cached = pictureAreaCache.area(for: key) {
            detectedPictureArea = cached
            if cached.isFullFrame { pictureAreaScanState = .finished }
        }
        applyPicture()
    }

    func startPictureAreaScanIfNeeded() {
        guard pictureAreaTask == nil,
              Self.shouldScanPictureArea(choice: activePictureChoice, isPlaying: state == .playing,
                                         isLive: isLive, isAudioOnly: isAudioOnly) else { return }
        guard detectedPictureArea?.isFullFrame != true else {
            pictureAreaScanState = .finished
            return
        }
        let size = videoSize
        guard pictureAreaScanState != .unavailable else { return }
        guard engine.duration > 0, size.width > 0, size.height > 0 else { return }
        // Its own extractor: one in-flight decode per extractor, and a scan sample must never cancel
        // the scrub preview the viewer is looking at.
        guard let extractor = engine.makeFrameExtractor() else {
            DiagnosticsLog.shared.note("[PictureArea] no scan: this source gives no second reader")
            pictureAreaScanState = .unavailable
            return
        }
        pictureAreaExtractor = extractor
        DiagnosticsLog.shared.note("[PictureArea] scan started: duration=\(Int(engine.duration))s seeded=\(detectedPictureArea != nil)")
        _ = runPictureAreaScan(source: extractor, duration: engine.duration,
                               displayAspect: Double(size.width / size.height))
    }

    struct PictureAreaRun {
        let firstPass: Task<Void, Never>
        func firstPassDone() async { await firstPass.value }
    }

    @discardableResult
    func runPictureAreaScan(source: any StillSource, duration: Double, displayAspect: Double) -> PictureAreaRun {
        let scanner = PictureAreaScanner(source: source, duration: duration, displayAspect: displayAspect,
                                         seed: detectedPictureArea)
        let generation = pictureGeneration
        pictureAreaScanState = .scanning
        let first = Task { [weak self] in
            let area = await scanner.firstPass()
            guard !Task.isCancelled else { return }
            self?.acceptPictureArea(area, generation: generation)
        }
        pictureAreaTask = Task { [weak self] in
            await first.value
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pictureAreaLookAheadInterval)
                guard !Task.isCancelled, let self, self.pictureGeneration == generation else { return }
                if await scanner.current?.isFullFrame == true { return }
                guard self.activePictureChoice == .fill(.auto), self.state == .playing else { continue }
                if let wider = await scanner.advance(playhead: self.engine.clock.currentTime) {
                    self.acceptPictureArea(wider, generation: generation)
                }
            }
        }
        return PictureAreaRun(firstPass: first)
    }

    private func acceptPictureArea(_ area: PictureArea?, generation: Int) {
        guard pictureGeneration == generation, let area else { return }
        pictureAreaScanState = .finished
        guard area != detectedPictureArea else { return }
        detectedPictureArea = area
        applyPicture(animated: true)
        // Remembered only while History is on: it is a record of what was played.
        if PlaybackHistory.isEnabled(), let key = pictureAreaCacheKey { pictureAreaCache.store(area, for: key) }
    }

    func stopPictureAreaScan() {
        pictureAreaTask?.cancel()
        pictureAreaTask = nil
        let extractor = pictureAreaExtractor
        pictureAreaExtractor = nil
        Task { await extractor?.shutdown() }
    }
}
