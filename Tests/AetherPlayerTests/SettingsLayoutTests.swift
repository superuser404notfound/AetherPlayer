import XCTest
@testable import AetherPlayer

final class SettingsLayoutTests: XCTestCase {
    func testLeavesInsetBelowVisibleHeight() {
        XCTAssertEqual(settingsWindowMaxHeight(visibleHeight: 853), 773, accuracy: 0.001)
    }

    func testNeverBelowMinimumOnSmallScreens() {
        XCTAssertEqual(settingsWindowMaxHeight(visibleHeight: 300), 320, accuracy: 0.001)
    }

    func testGrowsOnLargeDisplays() {
        XCTAssertEqual(settingsWindowMaxHeight(visibleHeight: 1400), 1320, accuracy: 0.001)
    }
}
