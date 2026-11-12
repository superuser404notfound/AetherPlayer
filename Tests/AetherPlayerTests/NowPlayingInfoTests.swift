import XCTest
import MediaPlayer
import AetherEngine
@testable import AetherPlayer

final class NowPlayingInfoTests: XCTestCase {
    func testMapsCoreFields() {
        let meta = MediaMetadata(title: "Song", artist: "Artist", album: "Album", artworkData: nil)
        let info = nowPlayingIdentity(metadata: meta, fallbackTitle: "ignored", isAudio: true)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Song")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "Artist")
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "Album")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyMediaType] as? UInt, MPNowPlayingInfoMediaType.audio.rawValue)
    }

    func testFallbackTitleWhenNoMetadataTitle() {
        let info = nowPlayingIdentity(metadata: nil, fallbackTitle: "My File", isAudio: false)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "My File")
        XCTAssertNil(info[MPMediaItemPropertyArtist])
        XCTAssertEqual(info[MPNowPlayingInfoPropertyMediaType] as? UInt, MPNowPlayingInfoMediaType.video.rawValue)
    }

    func testEmptyFieldsAreLeftOut() {
        let meta = MediaMetadata(title: "", artist: "", album: nil, artworkData: nil)
        let info = nowPlayingIdentity(metadata: meta, fallbackTitle: "File", isAudio: true)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "File")
        XCTAssertNil(info[MPMediaItemPropertyArtist])
    }

    /// The clock belongs to the engine now; a host-side elapsed or rate would fight its publisher.
    func testCarriesNoClock() {
        let info = nowPlayingIdentity(metadata: nil, fallbackTitle: "x", isAudio: false)
        XCTAssertNil(info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
        XCTAssertNil(info[MPNowPlayingInfoPropertyPlaybackRate])
        XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])
    }
}
