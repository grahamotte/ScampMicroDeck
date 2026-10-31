import XCTest
@testable import ScampMicroDeckCore

final class PlaybackTrackTests: XCTestCase {
    func testNormalizesMetadata() {
        let url = URL(fileURLWithPath: "/Music/02 Song.mp3")
        let track = PlaybackTrack(url: url, duration: -4, albumTitle: "  Album  ")

        XCTAssertEqual(track.id, url)
        XCTAssertEqual(track.displayName, "02 Song")
        XCTAssertEqual(track.sortName, "02 Song.mp3")
        XCTAssertEqual(track.duration, 0)
        XCTAssertEqual(track.albumTitle, "Album")
    }

    func testDropsBlankAlbumTitle() {
        XCTAssertNil(PlaybackTrack(url: URL(fileURLWithPath: "/song.mp3"), albumTitle: "  ").albumTitle)
    }
}
