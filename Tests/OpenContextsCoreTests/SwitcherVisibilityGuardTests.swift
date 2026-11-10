import XCTest
@testable import OpenContextsCore

final class SwitcherVisibilityGuardTests: XCTestCase {
    func testVisiblePanelKeepsTheSession() {
        var visibility = SwitcherVisibilityGuard()
        XCTAssertEqual(visibility.resolve(onScreen: 1, expected: 1), .keep)
        XCTAssertFalse(visibility.didRebuild)
    }

    func testInvisiblePanelIsRebuiltOnceThenTheSessionIsCancelled() {
        var visibility = SwitcherVisibilityGuard()
        XCTAssertEqual(visibility.resolve(onScreen: 0, expected: 1), .rebuildAndRetry)
        XCTAssertTrue(visibility.didRebuild)
        XCTAssertEqual(visibility.resolve(onScreen: 0, expected: 1), .cancel)
    }

    func testSessionContinuesWhenTheRebuiltPanelIsVisible() {
        var visibility = SwitcherVisibilityGuard()
        XCTAssertEqual(visibility.resolve(onScreen: 0, expected: 1), .rebuildAndRetry)
        XCTAssertEqual(visibility.resolve(onScreen: 1, expected: 1), .keep)
    }

    func testPartlyVisiblePanelsAreRebuiltButNeverCancelTheSession() {
        var visibility = SwitcherVisibilityGuard()
        XCTAssertEqual(visibility.resolve(onScreen: 1, expected: 2), .rebuildAndRetry)
        XCTAssertEqual(visibility.resolve(onScreen: 1, expected: 2), .keep)
    }

    func testMissingTargetPanelsAreRebuiltThenTheSessionIsCancelled() {
        var visibility = SwitcherVisibilityGuard()
        XCTAssertEqual(visibility.resolve(onScreen: 0, expected: 0), .rebuildAndRetry)
        XCTAssertEqual(visibility.resolve(onScreen: 0, expected: 0), .cancel)
    }
}
