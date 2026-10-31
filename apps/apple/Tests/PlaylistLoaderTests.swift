import Foundation
import XCTest
@testable import ScampMicroDeckCore

final class PlaylistLoaderTests: XCTestCase {
    func testLoadsTracksAndArtwork() async throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../App/Resources/Demo Album")
            .standardizedFileURL
        let loader = PlaylistLoader()

        let tracks = try await loader.loadTracks(from: folder)
        let artwork = try loader.loadFirstArtworkURL(from: folder)

        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks.map(\.sortName), tracks.map(\.sortName).sorted())
        XCTAssertTrue(tracks.allSatisfy { $0.duration > 0 })
        XCTAssertEqual(artwork?.lastPathComponent, "cover.jpg")
    }

    func testIgnoresNonMediaFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("text".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let loader = PlaylistLoader()
        let tracks = try await loader.loadTracks(from: folder)

        XCTAssertEqual(tracks, [])
        XCTAssertNil(try loader.loadFirstArtworkURL(from: folder))
    }
}
