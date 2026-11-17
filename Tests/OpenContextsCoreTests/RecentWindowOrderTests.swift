import XCTest
@testable import OpenContextsCore

final class RecentWindowOrderTests: XCTestCase {
    private let ids = ["A", "B", "C"]

    private func focused(on id: String) -> RecentWindowOrder {
        var order = RecentWindowOrder()
        order.update(windowIDs: ids, focusedID: id, now: 0)
        return order
    }

    func testFocusMovesWindowToFrontAndKeepsOthersInOrder() {
        var order = focused(on: "A")
        order.update(windowIDs: ids + ["D"], focusedID: "C", now: 1)
        XCTAssertEqual(order.ids, ["C", "A", "B", "D"])
        order.update(windowIDs: ["B", "C", "D"], focusedID: nil, now: 2)
        XCTAssertEqual(order.ids, ["C", "B", "D"])
        XCTAssertNil(order.focusedID)
    }

    func testFocusChangesDuringRequestedSwitchDoNotDisplacePreviousWindow() {
        var order = focused(on: "A")
        order.beginActivation("B")
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        // Before B gets focus the scan still sees A; the desktop switch then briefly restores C.
        order.update(windowIDs: ids, focusedID: "A", now: 0.1)
        order.update(windowIDs: ids, focusedID: "C", now: 0.3)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        XCTAssertEqual(order.focusedID, "B")
        order.finishActivation(now: 1.5)
        order.update(windowIDs: ids, focusedID: "B", now: 1.6)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        order.update(windowIDs: ids, focusedID: "C", now: 2)
        XCTAssertEqual(order.ids, ["C", "B", "A"])
    }

    func testCancelledSwitchRecordsFocusAgain() {
        var order = focused(on: "A")
        order.beginActivation("B")
        order.cancelActivation()
        order.update(windowIDs: ids, focusedID: "C", now: 0.2)
        XCTAssertEqual(order.ids, ["C", "B", "A"])
    }

    func testSwitchThatNeverGetsFocusStopsHoldingAfterTimeout() {
        var order = focused(on: "A")
        order.beginActivation("B")
        order.finishActivation(now: 1)
        order.update(windowIDs: ids, focusedID: "A", now: 1.2)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        order.update(windowIDs: ids, focusedID: "A", now: 2)
        XCTAssertEqual(order.ids, ["A", "B", "C"])
        XCTAssertEqual(order.focusedID, "A")
    }
}

final class FrontmostFocusTests: XCTestCase {
    private func window(_ id: String, pid: Int32) -> WindowInfo {
        WindowInfo(id: id, appID: "app\(pid)", appName: "App \(pid)", title: id, processID: pid)
    }

    /// Switched A → B with the switcher, then opened C outside it before a scan noticed.
    private func staleOrder() -> (order: RecentWindowOrder, windows: [WindowInfo]) {
        let windows = [window("A", pid: 1), window("B", pid: 2), window("C", pid: 3)]
        var order = RecentWindowOrder()
        order.update(windowIDs: windows.map(\.id), focusedID: "A", now: 0)
        order.update(windowIDs: windows.map(\.id), focusedID: "B", now: 1)
        return (order, order.ids.compactMap { id in windows.first { $0.id == id } })
    }

    func testQuickSwitchFromAppActivatedOutsideSwitcherReturnsToPreviousApp() {
        var (order, windows) = staleOrder()
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        let focus = RecentWindowOrder.focusedID(observed: "B", frontmostProcessID: 3, windows: windows)
        order.update(windowIDs: order.ids, focusedID: focus, now: 2)
        let ordered = order.ids.compactMap { id in windows.first { $0.id == id } }
        let start = WindowSwitcher.start(ordered, allSpaces: false, focusedID: order.focusedID, reverse: false)
        XCTAssertEqual(start.results[start.selectedIndex].window.id, "B")
    }

    func testQuickSwitchFromAppWithoutKnownWindowsReturnsToPreviousApp() {
        let (order, windows) = staleOrder()
        let focus = RecentWindowOrder.focusedID(observed: "B", frontmostProcessID: 4, windows: windows)
        let start = WindowSwitcher.start(windows, allSpaces: false, focusedID: focus, reverse: false)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        XCTAssertEqual(start.results[start.selectedIndex].window.id, "B")
    }

    func testObservedFocusIsKeptWhenItBelongsToFrontmostAppOrFrontmostIsUnknown() {
        let windows = [window("B1", pid: 2), window("B2", pid: 2), window("A", pid: 1)]
        XCTAssertEqual(RecentWindowOrder.focusedID(observed: "B2", frontmostProcessID: 2, windows: windows), "B2")
        XCTAssertEqual(RecentWindowOrder.focusedID(observed: "A", frontmostProcessID: nil, windows: windows), "A")
        XCTAssertNil(RecentWindowOrder.focusedID(observed: nil, frontmostProcessID: 2, windows: windows))
    }
}
