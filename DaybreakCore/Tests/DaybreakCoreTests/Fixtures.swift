import Foundation
@testable import DaybreakCore

enum Fixtures {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// 2026-11-18 09:00 in Los Angeles.
    static var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
    }

    static func todo(_ id: String, _ title: String? = nil, deadline: Date? = nil, project: String? = nil, tags: [String] = []) -> ThingsTodo {
        ThingsTodo(id: id, title: title ?? "Task \(id)", projectName: project, tags: tags, deadline: deadline)
    }
}
