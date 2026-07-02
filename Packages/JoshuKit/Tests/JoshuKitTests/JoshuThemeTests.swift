import XCTest
@testable import JoshuKit

final class JoshuThemeTests: XCTestCase {
    func testShadowInsetLeavesRoomForShadowRadius() {
        // Shadow radius used by the chrome is 24 with y-offset 10; the inset
        // must be large enough that the shadow isn't clipped at the panel edge.
        XCTAssertGreaterThanOrEqual(JoshuTheme.shadowInset, 24)
    }
}
