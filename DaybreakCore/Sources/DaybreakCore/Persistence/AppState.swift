import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var pomodoro: PomodoroSettings
    public var workdayEndHour: Int
    public var workdayEndMinute: Int

    public init(pomodoro: PomodoroSettings = PomodoroSettings(), workdayEndHour: Int = 18, workdayEndMinute: Int = 0) {
        self.pomodoro = pomodoro
        self.workdayEndHour = workdayEndHour
        self.workdayEndMinute = workdayEndMinute
    }

    public var workdayEnd: DateComponents {
        DateComponents(hour: workdayEndHour, minute: workdayEndMinute)
    }
}

/// Everything Daybreak saves between launches.
public struct AppState: Codable, Equatable, Sendable {
    public var plan: DayPlan
    public var journal: [JournalEntry]
    public var settings: AppSettings

    public init(plan: DayPlan, journal: [JournalEntry] = [], settings: AppSettings = AppSettings()) {
        self.plan = plan
        self.journal = journal
        self.settings = settings
    }

    /// Fresh state for `today`.
    public static func initial(today: DayKey) -> AppState {
        AppState(plan: .empty(for: today))
    }

    /// Whether the saved plan belongs to an earlier day and was begun but never wrapped up.
    public func hasUnfinishedPreviousDay(today: DayKey) -> Bool {
        plan.day < today && plan.phase == .active
    }

    /// Moves to a new day when that needs no input: an un-begun or ended plan from an
    /// earlier day is replaced with an empty one. A begun, un-wrapped day is kept so the
    /// user can wrap it up.
    public mutating func rollOver(to today: DayKey) {
        guard plan.day < today, plan.phase != .active else { return }
        plan = .empty(for: today)
    }

    public mutating func addToJournal(_ entry: JournalEntry) {
        journal.removeAll { $0.day == entry.day }
        journal.append(entry)
        journal.sort { $0.day < $1.day }
    }
}

/// Saves a Codable value as JSON, atomically.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Returns nil when nothing has been saved yet. If the file can't be decoded (e.g. after
    /// an incompatible update), it's moved aside to `<name>.bak` and nil is returned.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public enum AppPaths {
    /// `~/Library/Application Support/Daybreak/state.json`
    public static func stateFile() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("Daybreak", isDirectory: true).appendingPathComponent("state.json")
    }
}
