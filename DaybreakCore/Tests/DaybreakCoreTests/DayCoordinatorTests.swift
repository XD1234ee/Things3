import XCTest
@testable import DaybreakCore

final class DayCoordinatorTests: XCTestCase {
    func makeThings() -> FakeThingsClient {
        FakeThingsClient([
            (Fixtures.todo("today1"), .today),
            (Fixtures.todo("any1"), .anytime),
            (Fixtures.todo("inbox1"), .inbox),
        ])
    }

    func makePlan(_ ids: [String]) -> DayPlan {
        var plan = DayPlan.empty(for: DayKey(rawValue: "2026-11-18"))
        ids.forEach { plan.add(Fixtures.todo($0)) }
        return plan
    }

    func testBeginDayMovesPickedTasksToToday() async throws {
        let things = makeThings()
        let coordinator = DayCoordinator(things: things)
        let plan = try await coordinator.beginDay(makePlan(["today1", "any1", "inbox1"]), alreadyInToday: ["today1"], now: Fixtures.morning)

        XCTAssertEqual(plan.phase, .active)
        XCTAssertEqual(plan.begunAt, Fixtures.morning)
        let calls = await things.calls
        XCTAssertEqual(calls, ["move:any1:today", "move:inbox1:today"])
        let inboxList = await things.list(of: "inbox1")
        XCTAssertEqual(inboxList, .today)
    }

    func testBeginDayFailureLeavesPlanUnstarted() async {
        let things = makeThings()
        await things.failNextWrite(with: .permissionDenied)
        let coordinator = DayCoordinator(things: things)
        do {
            _ = try await coordinator.beginDay(makePlan(["any1"]), alreadyInToday: [], now: Fixtures.morning)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ThingsError, .permissionDenied)
        }
    }

    func testCompleteMarksDoneInThingsAndPlan() async throws {
        let things = makeThings()
        let coordinator = DayCoordinator(things: things)
        let plan = try await coordinator.complete("any1", in: makePlan(["any1", "inbox1"]), now: Fixtures.morning)
        XCTAssertEqual(plan.task("any1")?.outcome, .completed)
        XCTAssertEqual(plan.task("any1")?.completedAt, Fixtures.morning)
        XCTAssertEqual(plan.current?.id, "inbox1")
        let status = await things.todosByID["any1"]?.status
        XCTAssertEqual(status, .completed)
    }

    func testPostponeTomorrow() async throws {
        let things = makeThings()
        let coordinator = DayCoordinator(things: things)
        let plan = try await coordinator.postpone("any1", to: .tomorrow, in: makePlan(["any1"]))
        XCTAssertEqual(plan.task("any1")?.outcome, .postponedTomorrow)
        let list = await things.list(of: "any1")
        XCTAssertEqual(list, .upcoming)
    }

    func testEndDaySendsLeftoversToAnytimeByDefault() async throws {
        let things = makeThings()
        let coordinator = DayCoordinator(things: things)
        var plan = try await coordinator.beginDay(makePlan(["today1", "any1", "inbox1"]), alreadyInToday: ["today1"], now: Fixtures.morning)
        plan = try await coordinator.complete("today1", in: plan, now: Fixtures.morning)
        plan.recordPomodoro(id: "today1")
        plan.recordFocus(id: "today1", seconds: 1500)

        let result = await coordinator.endDay(plan, destinations: ["inbox1": .someday], reflection: "  Good day  ", now: Fixtures.morning)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.plan.phase, .ended)
        XCTAssertEqual(result.plan.task("any1")?.outcome, .returnedToAnytime)
        XCTAssertEqual(result.plan.task("inbox1")?.outcome, .postponedSomeday)
        let anyList = await things.list(of: "any1")
        let inboxList = await things.list(of: "inbox1")
        XCTAssertEqual(anyList, .anytime)
        XCTAssertEqual(inboxList, .someday)

        XCTAssertEqual(result.entry.completedTitles, ["Task today1"])
        XCTAssertEqual(result.entry.unfinishedTitles, ["Task any1", "Task inbox1"])
        XCTAssertEqual(result.entry.pomodoros, 1)
        XCTAssertEqual(result.entry.focusSeconds, 1500)
        XCTAssertEqual(result.entry.reflection, "Good day")
    }

    func testEndDayReportsFailuresAndKeepsGoing() async {
        let things = makeThings()
        await things.failNextWrite(with: .timeout)
        let coordinator = DayCoordinator(things: things)
        let result = await coordinator.endDay(makePlan(["any1", "inbox1"]), reflection: "", now: Fixtures.morning)
        XCTAssertEqual(Array(result.failures.keys), ["any1"])
        XCTAssertEqual(result.plan.task("any1")?.outcome, .pending)
        XCTAssertEqual(result.plan.task("inbox1")?.outcome, .returnedToAnytime)
    }

    func testReconcilePicksUpChangesMadeInThings() async throws {
        let things = makeThings()
        let coordinator = DayCoordinator(things: things)
        var plan = makePlan(["today1", "any1", "inbox1"])

        var renamed = Fixtures.todo("today1", "Renamed")
        renamed.notes = "New notes"
        await things.externallyUpdate(renamed)
        var done = Fixtures.todo("any1")
        done.status = .completed
        await things.externallyUpdate(done)
        await things.externallyDelete(id: "inbox1")

        let changes = try await coordinator.reconcile(plan)
        plan.apply(changes, now: Fixtures.morning)

        XCTAssertEqual(plan.task("today1")?.title, "Renamed")
        XCTAssertEqual(plan.task("today1")?.notes, "New notes")
        XCTAssertEqual(plan.task("any1")?.outcome, .completed)
        XCTAssertEqual(plan.task("inbox1")?.outcome, .removedInThings)
    }

    func testAddDuringActiveDayMovesToToday() async throws {
        let things = makeThings()
        let coordinator = DayCoordinator(things: things)
        var plan = makePlan([])
        plan.phase = .active
        plan = try await coordinator.addDuringDay(Fixtures.todo("inbox1"), to: plan, alreadyInToday: false)
        XCTAssertTrue(plan.contains("inbox1"))
        let calls = await things.calls
        XCTAssertEqual(calls, ["move:inbox1:today"])
    }
}
