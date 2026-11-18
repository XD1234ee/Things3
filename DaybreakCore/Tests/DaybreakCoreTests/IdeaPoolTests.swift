import XCTest
@testable import DaybreakCore

final class IdeaPoolTests: XCTestCase {
    func testSectionsDeduplicateInPriorityOrder() {
        let soon = Fixtures.calendar.date(byAdding: .day, value: 2, to: Fixtures.morning)!
        let later = Fixtures.calendar.date(byAdding: .day, value: 10, to: Fixtures.morning)!
        let lists: [ThingsList: [ThingsTodo]] = [
            .today: [Fixtures.todo("t1")],
            // Anytime includes Today's to-dos, as in Things.
            .anytime: [Fixtures.todo("t1"), Fixtures.todo("a1"), Fixtures.todo("a2", deadline: soon)],
            .inbox: [Fixtures.todo("i1")],
            .upcoming: [Fixtures.todo("u1", deadline: soon), Fixtures.todo("u2", deadline: later)],
        ]
        let sections = IdeaPool.build(from: lists, now: Fixtures.morning, calendar: Fixtures.calendar)
        XCTAssertEqual(sections.map(\.kind), [.today, .deadlines, .inbox, .anytime])
        XCTAssertEqual(sections[0].todos.map(\.id), ["t1"])
        XCTAssertEqual(Set(sections[1].todos.map(\.id)), ["a2", "u1"])
        XCTAssertEqual(sections[2].todos.map(\.id), ["i1"])
        XCTAssertEqual(sections[3].todos.map(\.id), ["a1"])
        XCTAssertFalse(sections.flatMap(\.todos).contains { $0.id == "u2" }, "upcoming items only appear for deadlines")
    }

    func testOverdueCountsAsDeadline() {
        let yesterday = Fixtures.calendar.date(byAdding: .day, value: -1, to: Fixtures.morning)!
        let sections = IdeaPool.build(from: [.anytime: [Fixtures.todo("x", deadline: yesterday)]], now: Fixtures.morning, calendar: Fixtures.calendar)
        XCTAssertEqual(sections.map(\.kind), [.deadlines])
    }

    func testSearchMatchesTitleProjectAndTags() {
        let lists: [ThingsList: [ThingsTodo]] = [
            .anytime: [
                Fixtures.todo("1", "Write report"),
                Fixtures.todo("2", "Call mum", project: "Family"),
                Fixtures.todo("3", "Buy milk", tags: ["errand"]),
            ],
        ]
        func ids(_ query: String) -> [String] {
            IdeaPool.build(from: lists, now: Fixtures.morning, search: query, calendar: Fixtures.calendar).flatMap(\.todos).map(\.id)
        }
        XCTAssertEqual(ids("report"), ["1"])
        XCTAssertEqual(ids("family"), ["2"])
        XCTAssertEqual(ids("ERRAND"), ["3"])
        XCTAssertEqual(ids(""), ["1", "2", "3"])
    }
}
