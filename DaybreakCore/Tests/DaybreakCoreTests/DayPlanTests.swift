import XCTest
@testable import DaybreakCore

final class DayPlanTests: XCTestCase {
    func makePlan(_ ids: [String]) -> DayPlan {
        var plan = DayPlan.empty(for: DayKey(rawValue: "2026-11-18"))
        ids.forEach { plan.add(Fixtures.todo($0)) }
        return plan
    }

    func testAddIgnoresDuplicates() {
        var plan = makePlan(["a", "b"])
        plan.add(Fixtures.todo("a"))
        XCTAssertEqual(plan.tasks.map(\.id), ["a", "b"])
    }

    func testCurrentIsFirstPending() {
        var plan = makePlan(["a", "b", "c"])
        XCTAssertEqual(plan.current?.id, "a")
        plan.setOutcome(.completed, for: "a", at: Date())
        XCTAssertEqual(plan.current?.id, "b")
        XCTAssertEqual(plan.upNext.map(\.id), ["c"])
    }

    func testSkipMovesToBack() {
        var plan = makePlan(["a", "b", "c"])
        plan.skip(id: "a")
        XCTAssertEqual(plan.pending.map(\.id), ["b", "c", "a"])
    }

    func testMovePendingUsesOnMoveSemantics() {
        var plan = makePlan(["a", "b", "c", "d"])
        plan.movePending(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(plan.pending.map(\.id), ["b", "c", "a", "d"])
        plan.movePending(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(plan.pending.map(\.id), ["d", "b", "c", "a"])
    }

    func testMovePendingIgnoresFinishedTasks() {
        var plan = makePlan(["a", "b", "c"])
        plan.setOutcome(.completed, for: "a", at: Date())
        // Pending is [b, c]; move c to the front.
        plan.movePending(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(plan.pending.map(\.id), ["c", "b"])
        XCTAssertEqual(plan.completed.map(\.id), ["a"])
    }

    func testEstimatesAreClamped() {
        var plan = makePlan(["a"])
        plan.setEstimate(id: "a", to: 20)
        XCTAssertEqual(plan.task("a")?.estimate, 8)
        plan.setEstimate(id: "a", to: 0)
        XCTAssertEqual(plan.task("a")?.estimate, 1)
    }

    func testRemainingPomodoros() {
        var plan = makePlan(["a", "b"])
        plan.setEstimate(id: "a", to: 3)
        plan.setEstimate(id: "b", to: 2)
        plan.recordPomodoro(id: "a")
        XCTAssertEqual(plan.remainingPomodoros, 4)
        plan.setOutcome(.completed, for: "b", at: Date())
        XCTAssertEqual(plan.remainingPomodoros, 2)
    }

    func testRemoveOnlyRemovesPending() {
        var plan = makePlan(["a", "b"])
        plan.setOutcome(.completed, for: "a", at: Date())
        plan.remove(id: "a")
        plan.remove(id: "b")
        XCTAssertEqual(plan.tasks.map(\.id), ["a"])
    }

    func testDayKey() {
        XCTAssertEqual(DayKey(Fixtures.morning, calendar: Fixtures.calendar).rawValue, "2026-11-18")
        XCTAssertLessThan(DayKey(rawValue: "2026-11-17"), DayKey(rawValue: "2026-11-18"))
    }

    func testRollOver() {
        let today = DayKey(rawValue: "2026-11-18")
        var state = AppState.initial(today: DayKey(rawValue: "2026-11-17"))
        state.plan.add(Fixtures.todo("a"))
        state.rollOver(to: today)
        XCTAssertEqual(state.plan, .empty(for: today), "an un-begun plan from yesterday is discarded")

        var active = AppState.initial(today: DayKey(rawValue: "2026-11-17"))
        active.plan.phase = .active
        XCTAssertTrue(active.hasUnfinishedPreviousDay(today: today))
        active.rollOver(to: today)
        XCTAssertEqual(active.plan.day.rawValue, "2026-11-17", "a begun day is kept so it can be wrapped up")
    }

    func testStateRoundTripsThroughStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<AppState>(url: dir.appendingPathComponent("state.json"))
        XCTAssertNil(try store.load())

        var state = AppState.initial(today: DayKey(rawValue: "2026-11-18"))
        state.plan.add(Fixtures.todo("a"))
        state.plan.recordFocus(id: "a", seconds: 90.5)
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
    }

    func testCorruptStateIsMovedAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(try JSONFileStore<AppState>(url: url).load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
    }
}
