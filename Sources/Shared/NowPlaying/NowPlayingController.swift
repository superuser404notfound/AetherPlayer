import Foundation
import MediaPlayer
import AetherEngine
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Hands the engine what it cannot know for the system Now-Playing card: the file's identity and
/// cover, and the playlist's next/previous. The engine owns the card, its clock and the transport
/// commands on every route it plays (AetherEngine#1041): the audio hosts and the software host
/// everywhere, and native video on macOS, where no AVKit publishes for us. Native video on iOS stays
/// with AVKit (`PlayerHostController` stages `externalMetadata`).
///
/// Several player windows share one system surface; the engine hands it to the one that played or
/// was claimed last, so `claim()` only forwards the window becoming key.
@MainActor
final class NowPlayingController {
    struct Actions {
        let next: () -> Void
        let previous: () -> Void
    }

    private weak var engine: AetherEngine?
    private var actions: Actions?

    private struct Identity: Equatable {
        /// The file, so a playlist entry with the same tags as the previous one is still restaged: the
        /// engine's video-side identity does not outlive the previous item.
        let source: URL?
        let title: String
        let artist: String?
        let album: String?
        let artwork: Data?
        let isAudio: Bool
    }

    /// What was last staged, so the frequent state and metadata pushes do not restage an unchanged card.
    private var staged: Identity?
    private var stagedTracks: (next: Bool, previous: Bool)?

    /// Decoded cover, kept across pushes and rebuilt only when the bytes change: decoding a poster-sized
    /// cover on every push dominated the process once (AetherPlayer#2).
    private var artworkSource: Data?
    private var artwork: MPMediaItemArtwork?

    func configure(engine: AetherEngine, actions: Actions) {
        self.engine = engine
        self.actions = actions
    }

    func claim() {
        engine?.claimNowPlaying()
    }

    func updateAvailability(hasNext: Bool, hasPrevious: Bool) {
        guard let engine else { return }
        if let staged = stagedTracks, staged == (hasNext, hasPrevious) { return }
        stagedTracks = (hasNext, hasPrevious)
        var next: (@MainActor () -> Void)?
        var previous: (@MainActor () -> Void)?
        if hasNext { next = { [weak self] in self?.actions?.next() } }
        if hasPrevious { previous = { [weak self] in self?.actions?.previous() } }
        engine.setNowPlayingTrackCommands(next: next, previous: previous)
    }

    func update(source: URL?, metadata: MediaMetadata?, fallbackTitle: String) {
        guard let engine else { return }
        let isAudio = engine.playbackBackend == .audio
        let base = nowPlayingIdentity(metadata: metadata, fallbackTitle: fallbackTitle, isAudio: isAudio)
        let identity = Identity(
            source: source,
            title: base[MPMediaItemPropertyTitle] as? String ?? fallbackTitle,
            artist: base[MPMediaItemPropertyArtist] as? String,
            album: base[MPMediaItemPropertyAlbumTitle] as? String,
            artwork: metadata?.artworkData,
            isAudio: isAudio)
        guard staged != identity else { return }
        staged = identity
        refreshArtwork(identity.artwork)
        var info = base
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if isAudio, let placeholder = Self.placeholderArtwork {
            // An empty slot on the audio session path makes MediaPlayer decode the file's own embedded
            // cover lazily, and a corrupt one crashes it there.
            info[MPMediaItemPropertyArtwork] = placeholder
        }
        engine.setNowPlayingInfo(info)
    }

    func clear() {
        if staged != nil { engine?.setNowPlayingInfo([:]) }
        if stagedTracks != nil { engine?.setNowPlayingTrackCommands(next: nil, previous: nil) }
        staged = nil
        stagedTracks = nil
        artworkSource = nil
        artwork = nil
    }

    // MARK: - Artwork

    /// Decoded once per cover, and force-decoded here so an undecodable one is dropped instead of
    /// handed to MediaPlayer, which decodes lazily on its own thread and crashes on it.
    private func refreshArtwork(_ data: Data?) {
        guard artworkSource != data else { return }
        artworkSource = data
        artwork = data.flatMap(Self.decode).map(Self.makeArtwork)
    }

    #if canImport(UIKit)
    private static func decode(_ data: Data) -> UIImage? { UIImage(data: data)?.preparingForDisplay() }

    /// MediaPlayer calls the request handler on its own queue, so the closure must not be main-actor
    /// isolated; an isolated one traps the moment the system renders the artwork.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private static let placeholderArtwork: MPMediaItemArtwork? = {
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
    #else
    private static func decode(_ data: Data) -> NSImage? { NSImage(data: data) }

    private nonisolated static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// macOS has no session that would fall back to the file's own cover, so no placeholder is needed.
    private static let placeholderArtwork: MPMediaItemArtwork? = nil
    #endif
}
