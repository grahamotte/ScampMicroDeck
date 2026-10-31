import XCTest
@testable import ScampMicroDeckCore

@MainActor
final class PlaybackMediaRemoteBridgeTests: XCTestCase {
    func testClearsEmptyNowPlayingState() {
        let bridge = PlaybackMediaRemoteBridge()

        bridge.updateNowPlaying(
            trackTitle: nil,
            albumTitle: nil,
            artworkImage: nil,
            duration: -1,
            elapsedTime: -1,
            playbackRate: -1,
            isPlaying: false,
            canSkipNext: false,
            canSkipPrevious: false
        )
        bridge.clear()
    }
}
