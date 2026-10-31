import XCTest
@testable import ScampMicroDeckCore

@MainActor
final class AudioPlayerEngineTests: XCTestCase {
    func testUnloadedState() {
        let engine = AudioPlayerEngine()

        XCTAssertFalse(engine.hasLoadedTrack)
        XCTAssertEqual(engine.currentTime, 0)

        engine.pause()
        engine.resume(rate: 3, volume: -1)
        engine.seek(to: 10)
        engine.setPlaybackRate(3)
        engine.setPlaybackVolume(-1)
        engine.stop()

        XCTAssertFalse(engine.hasLoadedTrack)
        XCTAssertEqual(engine.currentTime, 0)
    }
}
