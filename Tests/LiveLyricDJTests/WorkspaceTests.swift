import AppKit
import XCTest
@testable import LiveLyricDJ

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testReservedSpaceLeavesSeratoClearOfBanner() throws {
        let screen = NSRect(x: 0, y: 24, width: 1440, height: 852)
        let banner = NSRect(x: 0, y: 796, width: 1440, height: 80)
        let slot = try XCTUnwrap(SeratoWorkspace.fittingFrame(
            bannerFrame: banner, visibleFrame: screen,
            minimumSize: NSSize(width: 1000, height: 700)
        ))
        XCTAssertFalse(slot.intersects(banner))
        XCTAssertEqual(banner.minY - slot.maxY, 8)
        XCTAssertTrue(screen.contains(slot))
    }

    @MainActor
    func testOversizedBannerDoesNotForceSeratoBelowMinimumHeight() {
        XCTAssertNil(SeratoWorkspace.fittingFrame(
            bannerFrame: NSRect(x: 0, y: 480, width: 1440, height: 420),
            visibleFrame: NSRect(x: 0, y: 24, width: 1440, height: 876),
            minimumSize: NSSize(width: 1000, height: 700)
        ))
    }

    @MainActor
    func testSecondaryDisplayWithNegativeCoordinates() throws {
        let screen = NSRect(x: -1920, y: -100, width: 1920, height: 1000)
        let banner = NSRect(x: -1800, y: 820, width: 1000, height: 80)
        let slot = try XCTUnwrap(SeratoWorkspace.fittingFrame(
            bannerFrame: banner, visibleFrame: screen,
            minimumSize: NSSize(width: 1000, height: 700)
        ))
        XCTAssertFalse(slot.intersects(banner))
        XCTAssertEqual(slot.minX, -1920)
        XCTAssertTrue(screen.contains(slot))
    }

    @MainActor
    func testFloatingBannerCannotTriggerUnexpectedWindowArrangement() {
        XCTAssertNil(SeratoWorkspace.fittingFrame(
            bannerFrame: NSRect(x: 0, y: 300, width: 1440, height: 80),
            visibleFrame: NSRect(x: 0, y: 24, width: 1440, height: 876),
            minimumSize: NSSize(width: 1000, height: 700)
        ))
    }
}
