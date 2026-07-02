import XCTest
@testable import JoshuKit

final class SnapEngineTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSnapsToScreenLeftEdge() {
        let proposed = CGRect(x: 7, y: 400, width: 200, height: 100)
        let snapped = SnapEngine.snappedFrame(proposed: proposed, others: [], screen: screen)
        XCTAssertEqual(snapped.origin.x, 0)
        XCTAssertEqual(snapped.origin.y, 400)
    }

    func testSnapsToScreenRightEdgeAccountingForInset() {
        // Glass right edge (frame.maxX - inset) lands on screen.maxX.
        let proposed = CGRect(x: 1440 - 200 + 30 - 5, y: 100, width: 200, height: 100)
        let snapped = SnapEngine.snappedFrame(
            proposed: proposed, others: [], screen: screen, inset: 30)
        XCTAssertEqual(snapped.maxX - 30, screen.maxX)
    }

    func testNoSnapBeyondThreshold() {
        let proposed = CGRect(x: 40, y: 40, width: 200, height: 100)
        let snapped = SnapEngine.snappedFrame(
            proposed: proposed, others: [], screen: screen, threshold: 12)
        XCTAssertEqual(snapped, proposed)
    }

    func testSnapsToNeighborPanelEdge() {
        let other = CGRect(x: 500, y: 300, width: 200, height: 200)
        // Our left edge 8pt away from the other's right edge (700).
        let proposed = CGRect(x: 708, y: 320, width: 200, height: 100)
        let snapped = SnapEngine.snappedFrame(proposed: proposed, others: [other], screen: screen)
        XCTAssertEqual(snapped.origin.x, 700)
    }

    func testPicksNearestTarget() {
        // 3pt from left screen edge, 10pt from a neighbor edge at 13 → screen wins.
        let other = CGRect(x: 13, y: 0, width: 100, height: 100)
        let proposed = CGRect(x: 3, y: 0, width: 200, height: 100)
        let snapped = SnapEngine.snappedFrame(proposed: proposed, others: [other], screen: screen)
        XCTAssertEqual(snapped.origin.x, 0)
    }
}
