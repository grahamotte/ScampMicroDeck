import XCTest
@testable import ScampMicroDeckCore

@MainActor
final class PlaybackControllerTests: XCTestCase {
    func testEmptyState() {
        let playback = PlaybackController()

        XCTAssertFalse(playback.hasPlaylist)
        XCTAssertFalse(playback.canPlayPrevious)
        XCTAssertFalse(playback.canPlayNext)
        XCTAssertNil(playback.currentTrackDisplayName)
        XCTAssertEqual(playback.trackDurations, [])
        XCTAssertEqual(playback.recordRotationDegrees(), 0)
        XCTAssertNil(playback.currentAlbumFolderURL)

        playback.play(atPlaylistProgress: 0.5)
        playback.seek(toPlaylistProgress: 0.5)
        playback.togglePlayPause()
        playback.playNext()
        playback.playPrevious()

        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.playlistProgress, 0)
    }

    func testLoadAlbumSelectsAlbumImmediately() {
        let playback = PlaybackController()
        let albumFolderURL = URL(fileURLWithPath: "/tmp/album", isDirectory: true)

        playback.loadAlbum(from: albumFolderURL)

        XCTAssertEqual(playback.currentAlbumFolderURL, albumFolderURL)
    }

    func testPlaylistProgressSnapsToNearestTrackStart() {
        let durations: [TimeInterval] = [10, 30, 60]

        XCTAssertEqual(
            PlaybackController.playlistProgressSnappedToNearestTrackStart(
                0.08,
                trackDurations: durations,
            ),
            0.1,
            accuracy: 0.000_001,
        )
        XCTAssertEqual(
            PlaybackController.playlistProgressSnappedToNearestTrackStart(
                0.37,
                trackDurations: durations,
            ),
            0.4,
            accuracy: 0.000_001,
        )
        XCTAssertEqual(
            PlaybackController.playlistProgressSnappedToNearestTrackStart(
                0.92,
                trackDurations: durations,
            ),
            0.4,
            accuracy: 0.000_001,
        )
    }

    func testPlaylistProgressSnapClampsProgressWithoutTracks() {
        XCTAssertEqual(
            PlaybackController.playlistProgressSnappedToNearestTrackStart(
                1.5,
                trackDurations: [],
            ),
            1,
        )
    }

    func testStageDemoAlbumReplacesPreviouslyStagedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
        let demoAlbumURL = root.appendingPathComponent("Demo Album", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: demoAlbumURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("new cover".utf8).write(to: resourcesURL.appendingPathComponent("cover.jpg"))
        try Data("old cover".utf8).write(to: demoAlbumURL.appendingPathComponent("cover.jpg"))
        try Data("stale art".utf8).write(to: demoAlbumURL.appendingPathComponent("artwork.png"))

        try PlaybackController.stageDemoAlbum(
            filenames: ["cover.jpg"],
            from: resourcesURL,
            to: demoAlbumURL,
        )

        XCTAssertEqual(
            try Data(contentsOf: demoAlbumURL.appendingPathComponent("cover.jpg")),
            Data("new cover".utf8),
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: demoAlbumURL.appendingPathComponent("artwork.png").path,
            ),
        )
    }
}
