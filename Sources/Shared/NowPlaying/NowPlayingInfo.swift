import Foundation
import MediaPlayer
import AetherEngine

/// The identity half of the system Now-Playing card, from the file's metadata. Clock, rate and
/// duration are the engine's (AetherEngine#1041), and the artwork is attached by the controller, which
/// decodes it once per cover, so this stays a pure, testable mapping of the scalar fields.
func nowPlayingIdentity(metadata: MediaMetadata?, fallbackTitle: String, isAudio: Bool) -> [String: Any] {
    let title = metadata?.title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
    var info: [String: Any] = [
        MPMediaItemPropertyTitle: title,
        MPNowPlayingInfoPropertyMediaType: (isAudio ? MPNowPlayingInfoMediaType.audio : .video).rawValue,
    ]
    if let artist = metadata?.artist, !artist.isEmpty { info[MPMediaItemPropertyArtist] = artist }
    if let album = metadata?.album, !album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = album }
    return info
}
