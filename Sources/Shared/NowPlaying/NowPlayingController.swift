#if os(macOS)
import Foundation
import MediaPlayer
import AppKit
import AetherEngine

/// Drives the macOS system Now-Playing surfaces (Control Center widget,
/// media keys) for every backend. On macOS, AVPlayer does not auto-
/// populate MPNowPlayingInfoCenter, so the host writes it directly. The
/// controller is metadata/clock agnostic: the view model pushes updates
/// and the remote-command callbacks route back into the view model.
///
/// The system surface is one per process and every player window has a
/// controller, so exactly one of them owns it: the player that started
/// playing or whose window became key last (`claim()`). The others stay
/// silent until the owner clears, and the next one to push takes over.
@MainActor
final class NowPlayingController {
    private let info = MPNowPlayingInfoCenter.default()
    private static let commands = MPRemoteCommandCenter.shared()
    private static var targetsInstalled = false
    private static weak var owner: NowPlayingController?
    private var actions: Actions?

    /// Decoded cover, kept across pushes and rebuilt only when the bytes change.
    /// `update` runs on the throttled clock tick (about once a second for the
    /// whole session), and decoding the embedded artwork there re-ran a full
    /// image decode every second for artwork that never changes. On a file with
    /// a poster-sized cover that dominated the process: measured 18.8% of a core
    /// against 5.8% for the same A/V without one, with PNG decoding 60% of all
    /// running samples (AetherPlayer#2). `NowPlayingView` already gates its own
    /// copy on the artwork bytes; this is the same gate on the system surface.
    private var artworkSource: Data?
    private var artwork: MPMediaItemArtwork?

    /// Store this player's actions. The command targets are installed once per
    /// process and call whichever controller owns the surface.
    func configure(engine _: AetherEngine, actions: Actions) {
        self.actions = actions
        Self.installTargets()
    }

    func claim() {
        Self.owner = self
    }

    /// True when this controller may write the surface, taking it over when nobody holds it.
    private func mayPublish() -> Bool {
        if Self.owner == nil { Self.owner = self }
        return Self.owner === self
    }

    private static func installTargets() {
        guard !targetsInstalled else { return }
        targetsInstalled = true

        func route(_ body: @escaping (Actions) -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
            { _ in
                guard let actions = owner?.actions else { return .noActionableNowPlayingItem }
                body(actions)
                return .success
            }
        }
        commands.playCommand.addTarget(handler: route { $0.play() })
        commands.pauseCommand.addTarget(handler: route { $0.pause() })
        commands.togglePlayPauseCommand.addTarget(handler: route { $0.toggle() })

        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipForwardCommand.addTarget(handler: route { $0.skip(10) })
        commands.skipBackwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.addTarget(handler: route { $0.skip(-10) })

        commands.nextTrackCommand.addTarget(handler: route { $0.next() })
        commands.previousTrackCommand.addTarget(handler: route { $0.previous() })

        commands.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent,
                  let actions = owner?.actions else { return .commandFailed }
            actions.seekTo(e.positionTime)
            return .success
        }
    }

    /// Enable/disable next/previous to match playlist availability.
    func updateAvailability(hasNext: Bool, hasPrevious: Bool) {
        guard mayPublish() else { return }
        let commands = Self.commands
        commands.nextTrackCommand.isEnabled = hasNext
        commands.previousTrackCommand.isEnabled = hasPrevious
    }

    /// Push the current metadata + clock to the system. Pass nil to clear.
    func update(metadata: MediaMetadata?, fallbackTitle: String,
                duration: Double, elapsed: Double, rate: Float) {
        guard mayPublish() else { return }
        var dict = nowPlayingInfo(
            metadata: metadata, fallbackTitle: fallbackTitle,
            duration: duration, elapsed: elapsed, rate: rate)
        if let data = metadata?.artworkData {
            if artworkSource != data {
                artworkSource = data
                artwork = NSImage(data: data).map { Self.makeArtwork($0) }
            }
            if let artwork { dict[MPMediaItemPropertyArtwork] = artwork }
        } else if artworkSource != nil {
            artworkSource = nil
            artwork = nil
        }
        info.nowPlayingInfo = dict
        info.playbackState = rate > 0 ? .playing : .paused
    }

    /// Wrap an image as `MPMediaItemArtwork`. MediaPlayer invokes the
    /// request handler on its own internal queue, so the closure must NOT
    /// be main-actor-isolated; otherwise Swift's actor-isolation runtime
    /// check traps (SIGTRAP) the moment MediaPlayer renders the artwork.
    /// A `nonisolated` context produces a plain, non-isolated closure.
    private nonisolated static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Clear the system surface on stop.
    func clear() {
        artworkSource = nil
        artwork = nil
        guard Self.owner === self else { return }
        Self.owner = nil
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
    }

    struct Actions {
        let play: () -> Void
        let pause: () -> Void
        let toggle: () -> Void
        let skip: (Double) -> Void
        let next: () -> Void
        let previous: () -> Void
        let seekTo: (Double) -> Void
    }
}
#else
import Foundation
import MediaPlayer
import UIKit
import AetherEngine

/// Drives the iOS lock screen and Control Center Now-Playing card for audio playback (#13).
///
/// Video needs nothing here: `PlayerHostController` is an `AVPlayerViewController`, AVKit owns
/// Now-Playing for the native path through `externalMetadata`, and the software host publishes
/// its own card (`ownsSoftwareNowPlaying`). Audio has no AVPlayerViewController behind it, so
/// before this the card simply never appeared. Two audio routes, as in Sodalite's music player:
///
/// - AVPlayer audio host: the engine owns an auto-publishing `MPNowPlayingSession`. Identity goes
///   through `setAudioNowPlayingInfo` (stamped on the AVPlayerItem), elapsed/rate/duration come
///   from the player, and the commands bind to the SESSION's center. A paused bare AVPlayer
///   loses the card unless a session holds it.
/// - FFmpeg audio host (Opus, Vorbis, ...): no AVPlayer and no session, so the shared info and
///   command centers are written directly, clock included.
///
/// MPRemoteCommandCenter delivers off the main thread, so every handler is built outside main-actor
/// isolation and hops to it; a main-isolated closure there traps with `_dispatch_assert_queue_fail`.
@MainActor
final class NowPlayingController {
    struct Actions {
        let play: () -> Void
        let pause: () -> Void
        let toggle: () -> Void
        let skip: (Double) -> Void
        let next: () -> Void
        let previous: () -> Void
        let seekTo: (Double) -> Void
    }

    private weak var engine: AetherEngine?
    private var actions: Actions?

    /// The command center the handlers are bound to, and their tokens, so a route change can
    /// unbind them. Left on the shared center they would answer the software video host's
    /// commands too, which registers its own there.
    private var boundCenter: MPRemoteCommandCenter?
    private var boundTargets: [(MPRemoteCommand, Any)] = []

    /// What was last staged on the session path, so the per-second tick does not re-stamp an
    /// unchanged dictionary on the player item.
    private var stagedIdentity: Identity?
    private var wroteSharedCenter = false

    private var artworkSource: Data?
    private var artwork: MPMediaItemArtwork?
    private var hasNext = false
    private var hasPrevious = false

    private struct Identity: Equatable {
        let title: String
        let artist: String?
        let album: String?
        let artwork: Data?
        let duration: Double
    }

    func configure(engine: AetherEngine, actions: Actions) {
        self.engine = engine
        self.actions = actions
    }

    func claim() {}

    func updateAvailability(hasNext: Bool, hasPrevious: Bool) {
        self.hasNext = hasNext
        self.hasPrevious = hasPrevious
        applyAvailability()
    }

    private func applyAvailability() {
        guard let center = boundCenter else { return }
        center.nextTrackCommand.isEnabled = hasNext
        center.previousTrackCommand.isEnabled = hasPrevious
    }

    func update(metadata: MediaMetadata?, fallbackTitle: String,
                duration: Double, elapsed: Double, rate: Float) {
        guard let engine, engine.playbackBackend == .audio else {
            clear()
            return
        }
        let identity = Identity(
            title: metadata?.title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            artist: metadata?.artist,
            album: metadata?.album,
            artwork: metadata?.artworkData,
            duration: duration)
        refreshArtwork(identity.artwork)

        if let session = engine.audioNowPlayingSession {
            if wroteSharedCenter {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                wroteSharedCenter = false
            }
            bind(to: session.remoteCommandCenter)
            guard stagedIdentity != identity else { return }
            stagedIdentity = identity
            engine.setAudioNowPlayingInfo(identityInfo(identity))
            return
        }

        if stagedIdentity != nil {
            engine.setAudioNowPlayingInfo([:])
            stagedIdentity = nil
        }
        bind(to: MPRemoteCommandCenter.shared())
        var info = identityInfo(identity)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        wroteSharedCenter = true
    }

    func clear() {
        if stagedIdentity != nil {
            engine?.setAudioNowPlayingInfo([:])
            stagedIdentity = nil
        }
        if wroteSharedCenter {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            wroteSharedCenter = false
        }
        unbind()
        artworkSource = nil
        artwork = nil
    }

    // MARK: - Info

    /// Always carries an artwork: an empty slot makes the session fall back to decoding the asset's
    /// own embedded cover, and a corrupt one crashes MediaPlayer.
    private func identityInfo(_ identity: Identity) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: identity.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPMediaItemPropertyArtwork: artwork ?? Self.placeholderArtwork,
        ]
        if let artist = identity.artist, !artist.isEmpty { info[MPMediaItemPropertyArtist] = artist }
        if let album = identity.album, !album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = album }
        if identity.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = identity.duration }
        return info
    }

    /// Decoded once per cover, and force-decoded here so an undecodable one is dropped instead of
    /// handed to MediaPlayer, which decodes lazily on its own thread and crashes on it.
    private func refreshArtwork(_ data: Data?) {
        guard artworkSource != data else { return }
        artworkSource = data
        artwork = data.flatMap { UIImage(data: $0)?.preparingForDisplay() }.map(Self.makeArtwork)
    }

    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private static let placeholderArtwork: MPMediaItemArtwork = {
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.12, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 220)
            guard let glyph = UIImage(systemName: "music.note", withConfiguration: config)?
                .withTintColor(UIColor(white: 0.5, alpha: 1), renderingMode: .alwaysOriginal)
            else { return }
            glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2,
                                   y: (size.height - glyph.size.height) / 2))
        }
        return makeArtwork(image)
    }()

    // MARK: - Remote commands

    /// Binds the handlers to `center`, moving them off the previous one when the route changed.
    private func bind(to center: MPRemoteCommandCenter) {
        guard boundCenter !== center else { return }
        unbind()
        boundCenter = center
        let target = WeakController(self)
        func add(_ command: MPRemoteCommand, _ body: @escaping @MainActor (Actions) -> Void) {
            command.isEnabled = true
            boundTargets.append((command, command.addTarget(handler: Self.handler(target, body))))
        }
        add(center.playCommand) { $0.play() }
        add(center.pauseCommand) { $0.pause() }
        add(center.togglePlayPauseCommand) { $0.toggle() }
        add(center.nextTrackCommand) { $0.next() }
        add(center.previousTrackCommand) { $0.previous() }

        let position = center.changePlaybackPositionCommand
        position.isEnabled = true
        boundTargets.append((position, position.addTarget(handler: Self.positionHandler(target))))
        applyAvailability()
    }

    private func unbind() {
        for (command, token) in boundTargets { command.removeTarget(token) }
        boundTargets.removeAll()
        boundCenter = nil
    }

    private final class WeakController: @unchecked Sendable {
        weak var value: NowPlayingController?
        init(_ value: NowPlayingController) { self.value = value }
    }

    private nonisolated static func handler(
        _ target: WeakController,
        _ body: @escaping @MainActor (Actions) -> Void
    ) -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        return { _ in
            Task { @MainActor in
                guard let actions = target.value?.actions else { return }
                body(actions)
            }
            return .success
        }
    }

    private nonisolated static func positionHandler(
        _ target: WeakController
    ) -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in target.value?.actions?.seekTo(time) }
            return .success
        }
    }
}
#endif
