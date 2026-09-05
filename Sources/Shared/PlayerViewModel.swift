import Foundation
import Combine
import SwiftAssRenderer
#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif
import CoreGraphics
import AetherEngine

@Observable
@MainActor
final class PlayerViewModel {
    let engine: AetherEngine

    // Mirrored engine state (kept in sync via Combine).
    private(set) var state: PlaybackState = .idle
    /// Mirrors `engine.isLive`; drives the live transport bar (LIVE badge, DVR scrubbing).
    private(set) var isLive: Bool = false
    private(set) var currentTime: Double = 0
    /// Source-PTS clock for subtitle cue visibility. Differs from currentTime on disc titles,
    /// where currentTime is shifted by the clip-0 STC origin (sourcePresentationOrigin). (#112)
    private(set) var subtitleTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var audioTracks: [TrackInfo] = []
    private(set) var subtitleTracks: [TrackInfo] = []
    private(set) var activeAudioTrackIndex: Int?
    private(set) var backend: PlaybackBackend = .none
    private(set) var subtitleCues: [SubtitleCue] = []
    private(set) var isSubtitleActive: Bool = false
    /// Coded video dimensions for the subtitle overlay's bitmap-canvas mapping (.zero before load).
    var videoSize: CGSize {
        CGSize(width: Int(engine.sourceVideoWidth), height: Int(engine.sourceVideoHeight))
    }
    private(set) var metadata: MediaMetadata?
    /// How this session's audio reaches the renderer (AetherEngine AE#462). Read for the Stats row and
    /// for the one value that is a problem rather than a description, `.droppedNoPipeline`: the source
    /// has audio, none of it could be delivered, and before this published fact existed the session
    /// simply played silently with the reason only in the log.
    private(set) var audioDelivery: AudioDelivery = .none
    // Disc titles + chapters (#67); empty for non-disc sources.
    private(set) var discTitles: [TitleInfo] = []
    private(set) var selectedDiscTitleID: Int?
    private(set) var discChapters: [ChapterInfo] = []

    // Host-only state.
    private(set) var loadedURL: URL?
    private(set) var loadError: String?
    /// Engine index of the subtitle track the user picked (no published
    /// active-subtitle index exists, so we track it here).
    private(set) var selectedSubtitleIndex: Int?
    private(set) var activeSubtitleCodec: String?
    @ObservationIgnored private lazy var assCoordinator = ASSRenderCoordinator(player: engine)
    private(set) var assRenderer: AssSubtitlesRenderer?
    @ObservationIgnored private var sidecarASSHeaderCancellable: AnyCancellable?
    var assReloadSignal: PassthroughSubject<Void, Never> { assCoordinator.reloadSignal }
    private var assItemID: String { loadedURL?.lastPathComponent ?? "item" }

    private(set) var playlist: Playlist?
    private var folderScoped: ScopedResource?
    var hasNext: Bool { playlist?.hasNext ?? false }
    var hasPrevious: Bool { playlist?.hasPrevious ?? false }

    /// Repeat behavior for audio playback (off / repeat-all / repeat-one),
    /// cycled from the transport bar. Persisted across launches.
    private(set) var repeatMode: RepeatMode = .off

    /// Advance the repeat mode through its off -> all -> one -> off cycle.
    func cycleRepeatMode() {
        repeatMode = repeatMode.cycled
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "player.repeatMode")
    }

    /// Whether folder playback is shuffled. Persisted across launches and
    /// applied to the active folder playlist immediately when toggled.
    private(set) var shuffleEnabled: Bool = false

    func toggleShuffle() {
        shuffleEnabled.toggle()
        UserDefaults.standard.set(shuffleEnabled, forKey: "player.shuffle")
        playlist?.setShuffled(shuffleEnabled)
    }

    /// Lip-sync offset in seconds, positive presenting audio later than video. Persisted across
    /// launches and applied to every session, because the error it corrects belongs to the viewer's
    /// audio chain rather than to the file (see `AudioDelay`).
    private(set) var audioDelaySeconds: Double = 0

    /// Move the offset by one step and bring it to the running session.
    func adjustAudioDelay(by delta: Double) {
        setAudioDelay(AudioDelay.adjusted(audioDelaySeconds, by: delta))
    }

    func resetAudioDelay() { setAudioDelay(0) }

    /// True while a step in this direction would still change the value, so a control can go dead at
    /// the ceiling rather than accepting presses that do nothing.
    func canAdjustAudioDelay(by delta: Double) -> Bool {
        AudioDelay.adjusted(audioDelaySeconds, by: delta) != audioDelaySeconds
    }

    private func setAudioDelay(_ seconds: Double) {
        let value = AudioDelay.clamp(seconds)
        guard value != audioDelaySeconds else { return }
        audioDelaySeconds = value
        UserDefaults.standard.set(value, forKey: "playback.audioDelaySeconds")
        // The engine keeps the value for the next load even on the routes it cannot move timestamps on
        // (the remote-HLS bypass, an audio-only session), so this is called unconditionally and the
        // notice states what was set rather than what the route did with it.
        engine.setAudioDelay(value)
        showNotice(PlayerNotice(AudioDelay.noticeText(value)))
    }

    /// A short line shown over the picture and withdrawn again by whoever renders it.
    private(set) var notice: PlayerNotice?

    func showNotice(_ notice: PlayerNotice) { self.notice = notice }

    /// Withdraws the notice, unless a newer one replaced it while the timer ran.
    func dismissNotice(id: UUID) {
        if notice?.id == id { notice = nil }
    }

    /// User subtitle size choice, combined with the surface-relative auto
    /// scale in `SubtitleOverlayView`. Persisted across launches.
    private(set) var subtitleSize: SubtitleSize = .normal

    func setSubtitleSize(_ size: SubtitleSize) {
        subtitleSize = size
        UserDefaults.standard.set(size.rawValue, forKey: "player.subtitleSize")
    }

    #if os(iOS)
    /// Player rotation lock (lock-to-current). Persisted; default off (free rotation).
    private(set) var playerRotationLocked: Bool = UserDefaults.standard.bool(forKey: "player.rotationLocked")

    func setPlayerRotationLocked(_ locked: Bool) {
        playerRotationLocked = locked
        UserDefaults.standard.set(locked, forKey: "player.rotationLocked")
    }
    #endif

    let recents = RecentsStore()
    private let nowPlaying = NowPlayingController()
    /// One frame extractor per playback session, built from the playing file
    /// and shared by scrub preview and snapshot. Released (and shut down) on
    /// the next load and on stop().
    @ObservationIgnored private var frameExtractor: FrameExtractor?
    /// The disc title the current `frameExtractor` was built for. A disc still is pinned to the title
    /// its extractor opened, so switching titles must rebuild the extractor or snapshots keep showing
    /// the previous title (AetherEngine #105). nil for non-disc sources.
    @ObservationIgnored private var frameExtractorTitleID: Int?
    /// Scrub-preview source, reconfigured on each load.
    let scrubPreview = ScrubPreviewProvider()
    /// Decode + disk-cached thumbnails for the recents list.
    let recentsThumbnails = RecentsThumbnailProvider()
    private var scoped: ScopedResource?
    /// Set briefly after a resume so the UI can offer "Start over".
    private(set) var resumeMessage: String?
    private var lastPersist: Date = .distantPast

    var volume: Float {
        get { engine.volume }
        set {
            let clamped = max(0, min(1, newValue))
            engine.volume = clamped
            UserDefaults.standard.set(clamped, forKey: "player.volume")
        }
    }

    /// Playback speed. The engine has no published rate, so we mirror it
    /// locally; reset to 1x on each new load.
    private(set) var rate: Float = 1.0

    /// Volume captured before muting, so unmute restores it.
    private var preMuteVolume: Float?
    var isMuted: Bool { volume == 0 }

    /// Held while playing to keep the display and system awake during
    /// playback; released as soon as playback is not active. macOS only;
    /// iOS uses UIApplication.shared.isIdleTimerDisabled instead.
    #if os(macOS)
    private var sleepAssertion: NSObjectProtocol?
    #endif

    var isPlaying: Bool { state == .playing }
    var hasMedia: Bool { loadedURL != nil }
    /// A loaded file that has played to its natural end. The engine parks at
    /// `.ended` on end-of-stream (both backends); `.idle` is reserved for
    /// `stop()`/teardown but is included too since `loadedURL` only clears on
    /// `stop()`, so "loaded but idle" also reads as ended.
    var isEnded: Bool { Self.isEndedPlayback(state: state, hasMedia: hasMedia) }
    /// Natural end-of-playback: the engine parks at `.ended` on end-of-stream (and `.idle` is
    /// reserved for stop()/teardown). Kept as a static pure function so it is unit-testable.
    /// `nonisolated`: it touches no actor state, and the class's `@MainActor` default would
    /// otherwise force every call site (including plain synchronous unit tests) through await.
    nonisolated static func isEndedPlayback(state: PlaybackState, hasMedia: Bool) -> Bool {
        hasMedia && (state == .ended || state == .idle)
    }
    /// True when the session is presenting as audio-only (see isAudioPlayback).
    var isAudioOnly: Bool { isAudioPlayback(backend: backend, url: loadedURL) }

    private var cancellables = Set<AnyCancellable>()

    init() throws {
        self.engine = try AetherEngine()
        // Installs the engine's diagnostic sink for every configuration, not just DEBUG, and mirrors
        // it to a file the user can hand over. Shipped builds used to produce no diagnostics at all,
        // which is why playback reports could never be answered from a log (AetherPlayer#2).
        // stdout is kept in DEBUG so `devicectl process launch --console` still captures on device.
        DiagnosticsLog.shared.start()
        bind()
        if UserDefaults.standard.object(forKey: "player.volume") != nil {
            engine.volume = UserDefaults.standard.float(forKey: "player.volume")
        }
        if let raw = UserDefaults.standard.string(forKey: "player.repeatMode"),
           let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        shuffleEnabled = UserDefaults.standard.bool(forKey: "player.shuffle")
        if let raw = UserDefaults.standard.string(forKey: "player.subtitleSize"),
           let size = SubtitleSize(rawValue: raw) {
            subtitleSize = size
        }
        // Read through the clamp rather than trusted: this is a plain Double in the defaults, which a
        // downgrade or a hand-edited plist can leave out of range.
        audioDelaySeconds = AudioDelay.clamp(UserDefaults.standard.double(forKey: "playback.audioDelaySeconds"))
        nowPlaying.configure(actions: .init(
            play: { [weak self] in self?.engine.play() },
            pause: { [weak self] in self?.engine.pause() },
            toggle: { [weak self] in self?.primaryAction() },
            skip: { [weak self] d in self?.seek(by: d) },
            next: { [weak self] in Task { await self?.playNext() } },
            previous: { [weak self] in Task { await self?.playPrevious() } },
            seekTo: { [weak self] t in self?.seek(to: t) }
        ))
    }

    private func bind() {
        engine.$isLive.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.isLive = $0
        }.store(in: &cancellables)
        engine.$state.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.state = $0
            self?.updateSleepAssertion()
            if ($0 == .idle || $0 == .ended), self?.hasMedia == true {
                self?.handleTrackEnded()
            }
            self?.pushNowPlaying()
            #if os(iOS)
            // Take over the native volume overlay once playback is up so hardware volume presses show
            // our HUD. activate() is idempotent. During load the host is not parked (see startVolumeObservation).
            if $0 == .playing { PlayerSystemVolume.activate() }
            #endif
        }.store(in: &cancellables)
        // The playback clock lives on engine.clock (a separate
        // ObservableObject since AetherEngine#29) so its ~10 Hz ticks
        // only reach views that explicitly observe the clock.
        engine.clock.$currentTime.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.currentTime = $0
            self?.persistPositionThrottled()
            self?.pushNowPlayingThrottled()
        }.store(in: &cancellables)
        // Subtitle cue startTime/endTime are absolute source PTS (engine.sourceTime axis). On a
        // Blu-ray/disc title currentTime is source PTS minus the clip-0 STC origin, so comparing cues
        // against currentTime offsets them by that origin (11.6s / ~600s observed on #112 discs).
        // Drive the overlay off sourceTime so cues line up on discs and normal files alike.
        engine.clock.$sourceTime.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.subtitleTime = $0
        }.store(in: &cancellables)
        engine.$duration.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.duration = $0
            self?.pushNowPlaying()
        }.store(in: &cancellables)
        engine.$audioTracks.receive(on: DispatchQueue.main).sink { [weak self] in self?.audioTracks = $0 }.store(in: &cancellables)
        engine.$subtitleTracks.receive(on: DispatchQueue.main).sink { [weak self] in self?.subtitleTracks = $0 }.store(in: &cancellables)
        engine.$activeAudioTrackIndex.receive(on: DispatchQueue.main).sink { [weak self] in self?.activeAudioTrackIndex = $0 }.store(in: &cancellables)
        engine.$discTitles.receive(on: DispatchQueue.main).sink { [weak self] in self?.discTitles = $0 }.store(in: &cancellables)
        engine.$selectedDiscTitle.receive(on: DispatchQueue.main).sink { [weak self] in self?.selectedDiscTitleID = $0?.id }.store(in: &cancellables)
        engine.$discChapters.receive(on: DispatchQueue.main).sink { [weak self] in self?.discChapters = $0 }.store(in: &cancellables)
        engine.$playbackBackend.receive(on: DispatchQueue.main).sink { [weak self] in self?.backend = $0 }.store(in: &cancellables)
        engine.$subtitleCues.receive(on: DispatchQueue.main).sink { [weak self] in self?.subtitleCues = $0 }.store(in: &cancellables)
        engine.$isSubtitleActive.receive(on: DispatchQueue.main).sink { [weak self] in self?.isSubtitleActive = $0 }.store(in: &cancellables)
        engine.$metadata.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.metadata = $0
            self?.pushNowPlaying()
        }.store(in: &cancellables)
        engine.$audioDelivery.receive(on: DispatchQueue.main).sink { [weak self] delivery in
            self?.audioDelivery = delivery
            // A drop is announced once, when the session lands on it. The Stats row carries it for the
            // rest of the session, so a viewer who looked away is not left without an explanation.
            if let notice = PlayerNotice.forAudioDelivery(delivery) { self?.showNotice(notice) }
        }.store(in: &cancellables)
    }

    func open(url: URL, forceLive: Bool = false) async {
        await openInternal(url: url, recordPlaylistRelative: true, forceLive: forceLive)
    }

    /// DVR rewind window for live sessions (seconds).
    static let liveDVRWindowSeconds: Double = 1800

    /// Shared open path. Fresh opens make a new bookmark; reopening from a recent
    /// resolves a ScopedResource first (see openRecent). `startOverride` forces the
    /// start position (used by `restart()` to reload-to-replay at end-of-stream)
    /// instead of resolving a recents resume point. `forceLive` (Open URL toggle)
    /// loads straight on the engine's live path, skipping the VOD probe pass.
    private func openInternal(url: URL, recordPlaylistRelative: Bool, startOverride: Double? = nil, forceLive: Bool = false) async {
        loadError = nil
        // A notice describes the session that is going away, above all an audio drop, so it does not
        // survive into the next one.
        notice = nil
        // Name the source in the log without publishing it: a file contributes its name and not the
        // library layout around it, a remote source its scheme, host and name and not the query
        // string, which is where a session token would sit.
        DiagnosticsLog.shared.note(
            "open \(DiagnosticsLog.describe(url)) forceLive=\(forceLive)")
        // Known-live sources (user toggle or a previous session that resolved live) load
        // directly on the live path: one tune-in, and the reader skips its size-probe
        // ladder entirely. Everything else keeps the probe-then-reload fallback below.
        let openAsLive = forceLive || (!url.isFileURL && LiveStreamMemory.isKnownLive(url))
        let resume = openAsLive ? nil
            : startOverride ?? recents.position(for: url).flatMap { resumeTarget(lastPosition: $0.position, duration: $0.duration) }
        // Tear down the previous session's extractor up front so a failed
        // re-open does not strand it (it would otherwise linger until the
        // engine's 10 s idle-close).
        let previousExtractor = frameExtractor
        frameExtractor = nil
        scrubPreview.reset()
        if let previousExtractor { Task { await previousExtractor.shutdown() } }
        do {
            var options = LoadOptions(audioOnly: isAudioExtension(url))
            let bufferSegments = UserDefaults.standard.integer(forKey: "playback.forwardBufferSegments")
            if bufferSegments > 0 { options.forwardBufferSegments = bufferSegments }
            options.preserveASSMarkup = true
            // No container reliably declares E-AC-3 JOC, so the Stats inspector's channel row and the
            // track menu's Atmos label only mean anything if the session confirms it by decoding.
            options.confirmAtmos = true
            // The lip-sync offset is a property of the viewer's audio chain, so every session starts
            // with the one in force rather than at zero (AE#464).
            options.audioDelaySeconds = audioDelaySeconds
            // AE#455, off by default. The engine reports `supportsDolbyVision: false` for every Mac, so
            // a Profile 8.1 source is served here as its HDR10 base layer and the per-frame RPU never
            // reaches the panel. This is the switch that hands the composition to AVPlayer instead;
            // experimental, hence opt-in and read fresh on each open.
            options.forceDolbyVisionOnNonDVDisplay =
                UserDefaults.standard.bool(forKey: "playback.forceDolbyVisionOnNonDVDisplay")
            if openAsLive {
                options.isLive = true
                options.dvrWindowSeconds = Self.liveDVRWindowSeconds
            }
            let probe = try await engine.load(url: url, startPosition: resume, options: options)
            // Raw live source (e.g. a tuner MPEG-TS over HTTP): the probe flags no-duration
            // network streams; reload on the engine's live path so the clock, DVR ring, and
            // subtitles run with live semantics. Costs one extra tune-in only for live sources
            // that were not already known live.
            if let probe, probe.isLive, !engine.isLive {
                var liveOptions = options
                liveOptions.isLive = true
                liveOptions.dvrWindowSeconds = Self.liveDVRWindowSeconds
                try await engine.load(url: url, options: liveOptions)
            }
            // Remember resolved liveness so the next open of this URL skips the probe pass.
            if engine.isLive, !url.isFileURL {
                LiveStreamMemory.remember(url)
            }
            engine.play()
            loadedURL = url
            frameExtractor = engine.makeFrameExtractor()
            frameExtractorTitleID = engine.selectedDiscTitle?.id
            scrubPreview.configure(extractor: frameExtractor, enabled: frameExtractor != nil)
            selectedSubtitleIndex = nil
            activeSubtitleCodec = nil
            deactivateASSRendering()
            rate = 1.0
            engine.setRate(1.0)
            if let bm = BookmarkAccess.bookmark(for: url) {
                recents.record(url: url, bookmarkData: bm, duration: duration)
            }
            #if os(macOS)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            #endif
            if startOverride == nil, let resume { resumeMessage = "Resuming from \(formatTimecode(resume))" }
            else { resumeMessage = nil }
        } catch is CancellationError {
            // Superseded by a newer load or a deliberate cancel; not an error to surface.
            loadedURL = nil
            activeSubtitleCodec = nil
            deactivateASSRendering()
        } catch {
            loadError = "Could not play \(url.lastPathComponent): \(error.localizedDescription)"
            loadedURL = nil
            activeSubtitleCodec = nil
            deactivateASSRendering()
        }
    }

    /// Abort an in-flight open (Home's loading indicator). The engine load unwinds
    /// with CancellationError, which openInternal swallows.
    func cancelLoading() {
        engine.stop()
    }

    /// Reopen a recents entry: resolve its bookmark, hold scope, then load.
    func openRecent(_ item: RecentItem) async {
        scoped?.stop()
        guard let resource = ScopedResource(bookmark: item.bookmarkData) else {
            loadError = "Could not open \(item.name): the file may have moved or been deleted."
            return
        }
        scoped = resource
        await openInternal(url: resource.url, recordPlaylistRelative: true)
    }

    func startOver() {
        resumeMessage = nil
        seek(to: 0)
    }

    func dismissResumeMessage() { resumeMessage = nil }

    func togglePlayPause() {
        switch state {
        case .playing:
            flushPosition()
            engine.pause()
        case .paused: engine.play()
        default: break
        }
    }

    /// Replay from the beginning after the video has ended. The engine ignores seek()/play()
    /// from a parked `.ended` session (its contract is reload-to-replay), so re-open from 0.
    func restart() {
        guard let url = loadedURL else { return }
        Task {
            await openInternal(url: url, recordPlaylistRelative: false, startOverride: 0)
            setRate(1.0)
        }
    }

    /// The transport's primary action: replay if the video has ended,
    /// otherwise toggle play/pause. Backs the play button, the video tap,
    /// and the Space key so all three stay consistent at end-of-stream.
    func primaryAction() {
        if isEnded { restart() } else { togglePlayPause() }
    }

    func stop() {
        flushPosition()
        engine.stop()
        let extractorToClose = frameExtractor
        frameExtractor = nil
        frameExtractorTitleID = nil
        scrubPreview.reset()
        if let extractorToClose { Task { await extractorToClose.shutdown() } }
        scoped?.stop(); scoped = nil
        folderScoped?.stop(); folderScoped = nil
        playlist = nil
        loadedURL = nil
        loadError = nil
        resumeMessage = nil
        nowPlaying.clear()
        activeSubtitleCodec = nil
        deactivateASSRendering()
        #if os(iOS)
        hudKind = nil
        hudHideTask?.cancel()
        #endif
    }

    // MARK: - Live surfaces (session axis; the UI redraws on currentTime ticks)

    var seekableLiveRange: ClosedRange<Double>? { engine.seekableLiveRange }
    var isAtLiveEdge: Bool { engine.isAtLiveEdge }
    var behindLiveSeconds: Double { engine.behindLiveSeconds }

    func seekToLiveEdge() {
        Task { await engine.seekToLiveEdge() }
    }

    func seek(by delta: Double) {
        let target = max(0, min(duration, currentTime + delta))
        Task { await engine.seek(to: target) }
    }

    func seek(to seconds: Double) {
        Task { await engine.seek(to: seconds) }
    }

    func selectAudio(engineIndex: Int) {
        engine.selectAudioTrack(index: engineIndex)
    }

    func selectTitle(id: Int) {
        engine.selectTitle(id: id)
    }

    func selectChapter(id: Int) {
        engine.selectChapter(id: id)
    }

    func selectSubtitle(engineIndex: Int) {
        engine.selectSubtitleTrack(index: engineIndex)
        selectedSubtitleIndex = engineIndex
        let track = engine.subtitleTracks.first { $0.id == engineIndex }
        activeSubtitleCodec = track?.codec.lowercased()
        if activeSubtitleCodec == "ass" || activeSubtitleCodec == "ssa",
           let header = track?.assHeader, !header.isEmpty {
            assCoordinator.onRendererChanged = { [weak self] renderer in self?.assRenderer = renderer }
            assCoordinator.activate(header: header, itemID: assItemID)
            assRenderer = assCoordinator.renderer
        } else {
            deactivateASSRendering()
        }
    }

    func disableSubtitle() {
        engine.clearSubtitle()
        selectedSubtitleIndex = nil
        activeSubtitleCodec = nil
        deactivateASSRendering()
    }

    func loadSidecarSubtitle(url: URL) {
        engine.selectSidecarSubtitle(url: url)
        activeSubtitleCodec = url.pathExtension.lowercased()
        if activeSubtitleCodec == "ass" || activeSubtitleCodec == "ssa" {
            activateSidecarASSWhenHeaderArrives()
        } else {
            deactivateASSRendering()
        }
    }

    /// Activate styled ASS for a sidecar once the engine publishes its async header; strip fallback else.
    private func activateSidecarASSWhenHeaderArrives() {
        sidecarASSHeaderCancellable?.cancel()
        assCoordinator.onRendererChanged = { [weak self] renderer in self?.assRenderer = renderer }
        sidecarASSHeaderCancellable = engine.$sidecarASSHeader
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .first()
            .sink { [weak self] header in
                guard let self else { return }
                self.assCoordinator.activate(header: header, itemID: self.assItemID)
                self.assRenderer = self.assCoordinator.renderer
            }
    }

    func deactivateASSRendering() {
        sidecarASSHeaderCancellable?.cancel()
        sidecarASSHeaderCancellable = nil
        assCoordinator.deactivate()
        assRenderer = nil
    }

    // MARK: - Snapshot

    /// Capture the current frame at full resolution. Nil when nothing is
    /// loaded. Uses the session extractor's frame-accurate path.
    func snapshotCurrentFrame() async -> CGImage? {
        rebuildFrameExtractorIfDiscTitleChanged()
        guard let frameExtractor else { return nil }
        return await frameExtractor.snapshot(at: currentTime)
    }

    /// A disc title switch reloads the engine but keeps the session extractor, which is pinned to the
    /// title it opened, so its stills would keep showing the previous title (AetherEngine #105). Rebuild
    /// the extractor when the active disc title changed. Lazily invoked from the snapshot path, which the
    /// user triggers after the switch has settled, so `selectedDiscTitle` is already current.
    private func rebuildFrameExtractorIfDiscTitleChanged() {
        let currentTitleID = engine.selectedDiscTitle?.id
        guard currentTitleID != frameExtractorTitleID else { return }
        let previous = frameExtractor
        frameExtractor = engine.makeFrameExtractor()
        frameExtractorTitleID = currentTitleID
        scrubPreview.configure(extractor: frameExtractor, enabled: frameExtractor != nil)
        if let previous { Task { await previous.shutdown() } }
    }

    // MARK: - Folder / Playlist

    /// Open a folder: list playable files, sort, and play the first.
    func openFolder(_ folderURL: URL, bookmarkData: Data? = nil) async {
        folderScoped?.stop(); folderScoped = nil
        if let data = bookmarkData, let res = ScopedResource(bookmark: data) {
            folderScoped = res
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil)) ?? []
        let files = playableFiles(in: contents)
        guard !files.isEmpty else {
            loadError = "No playable files in \(folderURL.lastPathComponent)."
            return
        }
        let pl = Playlist(items: files, currentIndex: 0, isShuffled: shuffleEnabled)
        playlist = pl
        await openInternal(url: pl.current ?? files[0], recordPlaylistRelative: false)
    }

    /// Build a folder playlist around an already-open single file, given access
    /// to its parent folder (from a one-time prompt). Keeps the current file playing.
    func adoptFolderPlaylist(folderURL: URL, around currentURL: URL, bookmarkData: Data?) {
        folderScoped?.stop(); folderScoped = nil
        if let data = bookmarkData, let res = ScopedResource(bookmark: data) { folderScoped = res }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil)) ?? []
        let files = playableFiles(in: contents)
        let index = files.firstIndex { $0.standardizedFileURL == currentURL.standardizedFileURL } ?? 0
        playlist = files.isEmpty ? nil
            : Playlist(items: files, currentIndex: index, isShuffled: shuffleEnabled)
    }

    func playNext() async {
        flushPosition()
        guard var pl = playlist, let url = pl.next() else { return }
        playlist = pl
        await openInternal(url: url, recordPlaylistRelative: false)
    }

    func playPrevious() async {
        flushPosition()
        guard var pl = playlist, let url = pl.previous() else { return }
        playlist = pl
        await openInternal(url: url, recordPlaylistRelative: false)
    }

    /// Restart the folder playlist from its first track (repeat-all wrap).
    private func playPlaylistFirst() async {
        flushPosition()
        guard var pl = playlist, let url = pl.rewindToStart() else { return }
        playlist = pl
        await openInternal(url: url, recordPlaylistRelative: false)
    }

    /// Decide what happens when the current item reaches its natural end.
    /// Repeat behavior applies to audio only; video keeps the plain
    /// auto-advance-within-a-folder behavior.
    private func handleTrackEnded() {
        guard let url = loadedURL else { return }
        recents.markFinished(url)

        guard backend == .audio else {
            if playlist?.hasNext == true { Task { await playNext() } }
            return
        }

        switch repeatMode {
        case .one:
            restart()                                   // loop this track
        case .all:
            if playlist?.hasNext == true { Task { await playNext() } }
            else if playlist != nil { Task { await playPlaylistFirst() } }  // wrap
            else { restart() }                          // single file: loop it
        case .off:
            if playlist?.hasNext == true { Task { await playNext() } }
        }
    }

    // MARK: - Speed

    /// Available playback speeds offered in the UI.
    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    func setRate(_ newRate: Float) {
        engine.setRate(newRate)
        rate = newRate
        pushNowPlaying()
    }

    // MARK: - Volume

    func adjustVolume(by delta: Float) {
        if isMuted { preMuteVolume = nil }   // an explicit change cancels mute memory
        volume = volume + delta
    }

    func toggleMute() {
        if isMuted {
            volume = preMuteVolume ?? 1.0
            preMuteVolume = nil
        } else {
            preMuteVolume = volume
            volume = 0
        }
    }

    // MARK: - Errors

    func clearLoadError() {
        loadError = nil
    }

    // MARK: - Position persistence

    private func persistPositionThrottled() {
        guard let url = loadedURL, state == .playing else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPersist) >= 5 else { return }
        lastPersist = now
        recents.updatePosition(currentTime, duration: duration, for: url)
    }

    // MARK: - Now Playing

    private func pushNowPlaying() {
        guard hasMedia else { nowPlaying.clear(); return }
        nowPlaying.update(
            metadata: metadata,
            fallbackTitle: loadedURL.map { $0.deletingPathExtension().lastPathComponent } ?? "AetherPlayer",
            duration: duration,
            elapsed: currentTime,
            rate: isPlaying ? rate : 0)
        nowPlaying.updateAvailability(hasNext: hasNext, hasPrevious: hasPrevious)
    }

    private var lastNowPlayingPush: Date = .distantPast
    /// Throttled variant for the per-tick currentTime updates (at most ~1/s)
    /// so we do not rewrite MPNowPlayingInfoCenter on every playhead change.
    private func pushNowPlayingThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastNowPlayingPush) >= 1 else { return }
        lastNowPlayingPush = now
        pushNowPlaying()
    }

    /// Force-save the current position (call on pause, stop, window close).
    func flushPosition() {
        guard let url = loadedURL, currentTime > 0,
              !isEffectivelyFinished(position: currentTime, duration: duration) else { return }
        recents.updatePosition(currentTime, duration: duration, for: url)
    }

    // MARK: - Sleep prevention

    /// Disables idle display/system sleep while playing so the screen does
    /// not dim mid-video; releases the assertion the moment playback stops.
    private func updateSleepAssertion() {
        #if os(macOS)
        if state == .playing {
            if sleepAssertion == nil {
                // Video keeps the display awake; audio only blocks system
                // sleep so the screen may dim while music plays.
                let options: ProcessInfo.ActivityOptions = backend == .audio
                    ? [.idleSystemSleepDisabled]
                    : [.idleDisplaySleepDisabled, .idleSystemSleepDisabled]
                sleepAssertion = ProcessInfo.processInfo.beginActivity(
                    options: options, reason: "Media playback")
            }
        } else if let token = sleepAssertion {
            ProcessInfo.processInfo.endActivity(token)
            sleepAssertion = nil
        }
        #else
        // iOS: ProcessInfo.idleDisplaySleepDisabled has no effect; use the idle timer.
        // Audio-only playback lets the screen dim, so only video holds the timer.
        UIApplication.shared.isIdleTimerDisabled = (state == .playing && backend != .audio)
        #endif
    }

    #if os(iOS)
    enum PlayerHUDKind: Equatable { case brightness, volume, skipForward, skipBackward }

    /// Transient touch HUD (brightness/volume swipe, skip ripple); the overlay observes hudKind.
    var hudKind: PlayerHUDKind?
    var hudLevel: Double = 0
    /// The last shown kind, kept while the HUD is hidden. The overlay is permanently mounted and falls
    /// back to this when hudKind is nil, so it fades out on the same glyph it showed and never reveals
    /// an unrelated icon (the skip symbol) on the way in or out.
    var lastHudKind: PlayerHUDKind = .volume
    @ObservationIgnored private var hudHideTask: Task<Void, Never>?

    func flashHUD(_ kind: PlayerHUDKind, level: Double = 0) {
        hudKind = kind
        lastHudKind = kind
        hudLevel = level
        hudHideTask?.cancel()
        hudHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.hudKind = nil
        }
    }

    func setBrightness(_ value: CGFloat) {
        let clamped = min(max(value, 0), 1)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.screen.brightness = clamped
        flashHUD(.brightness, level: Double(clamped))
    }

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        PlayerSystemVolume.set(clamped)
        flashHUD(.volume, level: Double(clamped))
    }

    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?

    /// Mirror the system volume overlay with our own HUD on hardware volume-button presses, but only once
    /// we have taken over the native overlay (PlayerSystemVolume.isActive, i.e. the hidden MPVolumeView is
    /// parked, which happens at first `.playing` or on a volume swipe). While the video is still loading
    /// the host is not parked, so the native iOS overlay shows and this stays silent. Gating on isActive
    /// also swallows the activation-time settle callback without a timer.
    func startVolumeObservation() {
        volumeObservation?.invalidate()
        // @Sendable so the KVO callback is nonisolated (KVO fires off the main actor); it hops back via Task.
        let handler: @Sendable (AVAudioSession, NSKeyValueObservedChange<Float>) -> Void = { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor in
                guard let self, PlayerSystemVolume.isActive else { return }
                self.flashHUD(.volume, level: Double(newValue))
            }
        }
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new], changeHandler: handler)
    }

    func stopVolumeObservation() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        // Restore the native volume overlay for the rest of the app now that the player is gone.
        PlayerSystemVolume.deactivate()
    }
    #endif
}
