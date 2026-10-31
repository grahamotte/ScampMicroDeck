import XCTest
@testable import ScampMicroDeckCore

final class BlackRecordPressingTests: XCTestCase {
    func testTrackBandsPreserveAlbumBoundariesInPlaybackOrder() {
        let pressing = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [260, 180])

        XCTAssertEqual(pressing.bands.map(\.outerRadius), [300, 260, 180])
        XCTAssertEqual(pressing.bands.map(\.innerRadius), [260, 180, 100])
        XCTAssertEqual(pressing.bands.map(\.width), [40, 80, 80])
        XCTAssertEqual(pressing.gaps.map(\.radius), [260, 180])
        XCTAssertEqual(pressing.bands.map(\.midRadius), [280, 220, 140])
    }

    func testPressingIsStableAndChangesWithTheAlbum() {
        let pressing = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [260, 180])
        let sameAlbum = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [260, 180])
        let otherAlbum = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [240, 170])

        XCTAssertEqual(pressing, sameAlbum)
        XCTAssertNotEqual(pressing, otherAlbum)
        XCTAssertNotEqual(pressing.bands[0].grooves.first?.width, otherAlbum.bands[0].grooves.first?.width)
    }

    func testInvalidAndRepeatedDivisionsAreIgnoredAndSorted() {
        let pressing = BlackRecordPressing(
            innerRadius: 100,
            outerRadius: 300,
            divisionRadii: [.nan, .infinity, -.infinity, 300, 100, -20, 180, 260, 180]
        )

        XCTAssertEqual(pressing.gaps.map(\.radius), [260, 180])
        XCTAssertEqual(pressing.bands.count, 3)
    }

    func testSingleTrackAndUnavailableDivisionsStillHaveGrooves() {
        let pressing = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [])

        XCTAssertEqual(pressing.bands.count, 1)
        XCTAssertTrue(pressing.gaps.isEmpty)
        XCTAssertFalse(pressing.bands[0].grooves.isEmpty)
        XCTAssertLessThanOrEqual(pressing.bands[0].grooves.count, 3)
    }

    func testGroovesStayInsideTheirTrackAndClearOfSilentGaps() {
        let pressing = BlackRecordPressing(
            innerRadius: 100,
            outerRadius: 300,
            divisionRadii: [299.99, 260, 259.99, 180, 100.01]
        )

        for band in pressing.bands {
            XCTAssertGreaterThan(band.width, 0)
            for groove in band.grooves {
                XCTAssertGreaterThan(groove.width, 0)
                XCTAssertGreaterThan(groove.radius - groove.width / 2, band.innerRadius)
                XCTAssertLessThan(groove.radius + groove.width / 2, band.outerRadius)
                XCTAssertTrue((0...1).contains(groove.strength))
                for gap in pressing.gaps {
                    XCTAssertGreaterThan(abs(groove.radius - gap.radius), (groove.width + gap.width) / 2)
                }
            }
        }
        XCTAssertTrue(pressing.gaps.allSatisfy { $0.width > 0 && $0.width <= 2.7 })
    }

    func testSongGapsAreWiderThanDecorativeGrooves() {
        let pressing = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [260, 180])
        let widestGroove = pressing.bands.flatMap(\.grooves).map(\.width).max() ?? 0

        for gap in pressing.gaps {
            XCTAssertGreaterThan(gap.width, widestGroove * 4)
        }
    }

    func testInvalidGeometryProducesNoDrawingInstructions() {
        for bounds: (CGFloat, CGFloat) in [(0, 0), (100, 50), (-1, 100), (.nan, 100), (0, .infinity)] {
            let pressing = BlackRecordPressing(innerRadius: bounds.0, outerRadius: bounds.1, divisionRadii: [60])
            XCTAssertTrue(pressing.bands.isEmpty)
            XCTAssertTrue(pressing.gaps.isEmpty)
        }
    }

    func testResizingScalesTheSamePressingAndBoundsDrawingWork() {
        let small = BlackRecordPressing(innerRadius: 100, outerRadius: 300, divisionRadii: [260, 180])
        let large = BlackRecordPressing(innerRadius: 200, outerRadius: 600, divisionRadii: [520, 360])

        for (first, second) in zip(small.bands, large.bands) {
            XCTAssertEqual(first.grooves.count, second.grooves.count)
            for (groove, scaledGroove) in zip(first.grooves, second.grooves) {
                XCTAssertEqual(scaledGroove.radius, groove.radius * 2, accuracy: 0.0001)
                XCTAssertEqual(scaledGroove.width, groove.width * 2, accuracy: 0.0001)
            }
        }
        XCTAssertTrue(large.bands.allSatisfy { $0.grooves.count <= 3 })
    }
}
