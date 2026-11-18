import XCTest
@testable import DaybreakCore

final class PomodoroEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testFocusRunsTwentyFiveMinutesThenStartsShortBreak() {
        var engine = PomodoroEngine()
        engine.startFocus(at: t0)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(60)), 24 * 60)
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(24 * 60)))

        let event = engine.tick(at: t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(event, .focusCompleted(count: 1, nextBreak: .shortBreak))
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(25 * 60)), 5 * 60)
    }

    func testBreakEndsInIdle() {
        var engine = PomodoroEngine()
        engine.startFocus(at: t0)
        engine.tick(at: t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(30 * 60)), .breakCompleted)
        XCTAssertEqual(engine.phase, .idle)
    }

    func testEveryFourthPomodoroGetsALongBreak() {
        var engine = PomodoroEngine()
        var now = t0
        var breaks: [PomodoroPhase] = []
        for _ in 0..<4 {
            engine.startFocus(at: now)
            now = now.addingTimeInterval(engine.settings.focus)
            if case .focusCompleted(_, let next) = engine.tick(at: now) { breaks.append(next) }
            engine.skipBreak()
        }
        XCTAssertEqual(breaks, [.shortBreak, .shortBreak, .shortBreak, .longBreak])
        XCTAssertEqual(engine.completedFocusCount, 4)
    }

    func testPauseFreezesRemainingTime() {
        var engine = PomodoroEngine()
        engine.startFocus(at: t0)
        engine.pause(at: t0.addingTimeInterval(10 * 60))
        XCTAssertTrue(engine.isPaused)
        XCTAssertFalse(engine.isFocusRunning)
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(60 * 60)), 15 * 60)
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(60 * 60)))

        engine.resume(at: t0.addingTimeInterval(60 * 60))
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(60 * 60)), 15 * 60)
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(75 * 60)), .focusCompleted(count: 1, nextBreak: .shortBreak))
    }

    func testStopDoesNotCount() {
        var engine = PomodoroEngine()
        engine.startFocus(at: t0)
        engine.stop()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.completedFocusCount, 0)
    }

    func testProgress() {
        var engine = PomodoroEngine(settings: PomodoroSettings(focusMinutes: 10))
        XCTAssertEqual(engine.progress(at: t0), 0)
        engine.startFocus(at: t0)
        XCTAssertEqual(engine.progress(at: t0.addingTimeInterval(5 * 60)), 0.5, accuracy: 0.0001)
    }

    func testCapacityCountsPomodorosWithBreaks() {
        let calendar = Fixtures.calendar
        let settings = PomodoroSettings()
        // 9:00 → 11:00 is 120 min: 25+5, 25+5, 25+5, 25 (+15) = 4 pomodoros.
        let fits = Capacity.pomodorosThatFit(now: Fixtures.morning, workdayEnd: DateComponents(hour: 11, minute: 0), settings: settings, calendar: calendar)
        XCTAssertEqual(fits, 4)
        let late = Capacity.pomodorosThatFit(now: Fixtures.morning, workdayEnd: DateComponents(hour: 8, minute: 0), settings: settings, calendar: calendar)
        XCTAssertEqual(late, 0)
    }
}
