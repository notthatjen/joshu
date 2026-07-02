import XCTest
@testable import JoshuKit

final class PanelPlacementResolverTests: XCTestCase {
    private let main = ScreenInfo(uuid: "MAIN", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let second = ScreenInfo(uuid: "SECOND", visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))

    func testFractionRoundTripOnSameScreen() {
        let frame = CGRect(x: 144, y: 175, width: 400, height: 300)
        let placement = PanelPlacementResolver.placement(for: frame, screens: [main, second])
        XCTAssertEqual(placement.screenUUID, "MAIN")

        let resolved = PanelPlacementResolver.frame(
            for: placement, screens: [main, second], mainScreen: main)
        XCTAssertEqual(resolved, frame)
    }

    func testFractionSurvivesResolutionChange() {
        let frame = CGRect(x: 720, y: 437.5, width: 400, height: 300) // center-ish of MAIN
        let placement = PanelPlacementResolver.placement(for: frame, screens: [main])

        // Same screen, smaller resolution.
        let shrunk = ScreenInfo(uuid: "MAIN", visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 775))
        let resolved = PanelPlacementResolver.frame(for: placement, screens: [shrunk], mainScreen: shrunk)!
        // Same relative position, and fully on-screen.
        XCTAssertEqual(resolved.minX / 1280, 720 / 1440, accuracy: 0.001)
        XCTAssertTrue(shrunk.visibleFrame.contains(resolved))
    }

    func testMissingScreenFallsBackToMainAndClamps() {
        let frame = CGRect(x: 3000, y: 800, width: 400, height: 240) // far right of SECOND
        let placement = PanelPlacementResolver.placement(for: frame, screens: [main, second])
        XCTAssertEqual(placement.screenUUID, "SECOND")

        // SECOND unplugged: resolves on MAIN, clamped inside it.
        let resolved = PanelPlacementResolver.frame(for: placement, screens: [main], mainScreen: main)!
        XCTAssertTrue(main.visibleFrame.contains(resolved), "\(resolved) not inside \(main.visibleFrame)")
    }

    func testLegacyAbsoluteOriginResolvesAndClamps() {
        let placement = PanelPlacement(origin: CGPoint(x: 1300, y: 800), size: CGSize(width: 400, height: 300))
        let resolved = PanelPlacementResolver.frame(for: placement, screens: [main], mainScreen: main)!
        XCTAssertTrue(main.visibleFrame.contains(resolved))
    }

    func testNilPlacementMeansCascade() {
        let placement = PanelPlacement(size: CGSize(width: 400, height: 300))
        XCTAssertNil(PanelPlacementResolver.frame(for: placement, screens: [main], mainScreen: main))
    }

    func testClampKeepsOversizedPanelAtOrigin() {
        let huge = CGRect(x: 100, y: 100, width: 2000, height: 2000)
        let clamped = PanelPlacementResolver.clamp(huge, into: main.visibleFrame)
        XCTAssertEqual(clamped.origin, main.visibleFrame.origin)
    }
}
