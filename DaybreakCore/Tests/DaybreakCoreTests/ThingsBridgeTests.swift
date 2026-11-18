import XCTest
@testable import DaybreakCore

final class ThingsBridgeTests: XCTestCase {
    func testDecodesListsOutput() throws {
        let json = """
        {"today":[{"id":"A1","name":"Write report","notes":"Draft first","status":"open",
                   "deadline":"2026-11-20T08:00:00.000Z","startDate":null,"tags":"Work, Deep",
                   "project":"Q4 Review","area":null}],
         "inbox":[],
         "bogus":[]}
        """
        let lists = try ThingsBridgeDecoding.decodeLists(Data(json.utf8))
        XCTAssertEqual(lists.keys.sorted { $0.rawValue < $1.rawValue }, [.inbox, .today])
        let todo = try XCTUnwrap(lists[.today]?.first)
        XCTAssertEqual(todo.id, "A1")
        XCTAssertEqual(todo.title, "Write report")
        XCTAssertEqual(todo.notes, "Draft first")
        XCTAssertEqual(todo.tags, ["Work", "Deep"])
        XCTAssertEqual(todo.context, "Q4 Review")
        XCTAssertEqual(todo.deadline, ISO8601DateFormatter().date(from: "2026-11-20T08:00:00Z"))
        XCTAssertNil(todo.startDate)
    }

    func testDecodesLookupWithMissingItems() throws {
        let json = #"{"A1":{"id":"A1","name":"x","status":"completed","tags":""},"B2":null}"#
        let found = try ThingsBridgeDecoding.decodeLookup(Data(json.utf8))
        XCTAssertEqual(found.keys.sorted(), ["A1"])
        XCTAssertEqual(found["A1"]?.status, .completed)
        XCTAssertEqual(found["A1"]?.tags, [])
    }

    func testBadOutputThrows() {
        XCTAssertThrowsError(try ThingsBridgeDecoding.decodeLists(Data("oops".utf8))) { error in
            guard case .badOutput = error as? ThingsError else { return XCTFail("\(error)") }
        }
    }

    func testMapsOsascriptErrors() {
        XCTAssertEqual(ThingsBridgeDecoding.error(fromStderr: "execution error: Error: Error: Not authorized to send Apple events to Things3. (-1743)"), .permissionDenied)
        XCTAssertEqual(ThingsBridgeDecoding.error(fromStderr: "execution error: Error: Error: Application can't be found. (-2700)"), .notInstalled)
        XCTAssertEqual(ThingsBridgeDecoding.error(fromStderr: "execution error: Error: No to-do with id X (-2700)\n"), .scriptFailed("execution error: Error: No to-do with id X (-2700)"))
    }

    func testShowLink() {
        XCTAssertEqual(ThingsLinks.show(id: "abc 123")?.absoluteString, "things:///show?id=abc%20123")
    }

    func testBridgeScriptIsBundled() throws {
        let source = try String(contentsOf: ThingsBridgeScript.url)
        XCTAssertTrue(source.contains("function run(argv)"))
    }
}
