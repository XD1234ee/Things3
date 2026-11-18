import Foundation

/// A calendar day in the user's time zone, e.g. "2026-11-18".
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public var description: String { rawValue }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TaskOutcome: String, Codable, Sendable {
    case pending
    case completed
    case postponedTomorrow
    case postponedSomeday
    case returnedToAnytime
    /// Deleted or canceled in Things while it was planned.
    case removedInThings
}

public struct PlannedTask: Identifiable, Hashable, Codable, Sendable {
    /// The Things to-do ID.
    public var id: String
    public var title: String
    public var context: String?
    public var notes: String
    /// Estimate in pomodoros.
    public var estimate: Int
    public var outcome: TaskOutcome
    public var completedPomodoros: Int
    public var focusSeconds: TimeInterval
    public var completedAt: Date?

    public static let estimateRange = 1...8

    public init(todo: ThingsTodo, estimate: Int = 1) {
        id = todo.id
        title = todo.title
        context = todo.context
        notes = todo.notes
        self.estimate = min(max(estimate, Self.estimateRange.lowerBound), Self.estimateRange.upperBound)
        outcome = .pending
        completedPomodoros = 0
        focusSeconds = 0
        completedAt = nil
    }

    public var isPending: Bool { outcome == .pending }
}

public enum DayPhase: String, Codable, Sendable {
    /// Choosing tasks. Nothing has been written to Things yet.
    case planning
    /// "Begin Day" happened; working through the plan.
    case active
    /// The day was wrapped up.
    case ended
}

public struct DayPlan: Codable, Equatable, Sendable {
    public var day: DayKey
    public var phase: DayPhase
    /// Plan order. Pending tasks are worked on in this order.
    public var tasks: [PlannedTask]
    public var begunAt: Date?
    public var endedAt: Date?

    public init(day: DayKey, phase: DayPhase = .planning, tasks: [PlannedTask] = [], begunAt: Date? = nil, endedAt: Date? = nil) {
        self.day = day
        self.phase = phase
        self.tasks = tasks
        self.begunAt = begunAt
        self.endedAt = endedAt
    }

    public static func empty(for day: DayKey) -> DayPlan { DayPlan(day: day) }

    public var pending: [PlannedTask] { tasks.filter(\.isPending) }
    public var completed: [PlannedTask] { tasks.filter { $0.outcome == .completed } }
    /// The task being worked on: the first pending one.
    public var current: PlannedTask? { tasks.first(where: \.isPending) }
    public var upNext: [PlannedTask] { Array(pending.dropFirst()) }

    public var totalPomodoros: Int { tasks.reduce(0) { $0 + $1.completedPomodoros } }
    public var totalFocusSeconds: TimeInterval { tasks.reduce(0) { $0 + $1.focusSeconds } }

    /// Pomodoros still needed for pending tasks, according to their estimates.
    public var remainingPomodoros: Int {
        pending.reduce(0) { $0 + max(0, $1.estimate - $1.completedPomodoros) }
    }

    public func contains(_ id: String) -> Bool { tasks.contains { $0.id == id } }

    public func task(_ id: String) -> PlannedTask? { tasks.first { $0.id == id } }

    // MARK: - Editing the plan

    public mutating func add(_ todo: ThingsTodo, estimate: Int = 1) {
        guard !contains(todo.id) else { return }
        tasks.append(PlannedTask(todo: todo, estimate: estimate))
    }

    public mutating func remove(id: String) {
        tasks.removeAll { $0.id == id && $0.isPending }
    }

    public mutating func setEstimate(id: String, to estimate: Int) {
        update(id) { $0.estimate = min(max(estimate, PlannedTask.estimateRange.lowerBound), PlannedTask.estimateRange.upperBound) }
    }

    /// Reorders the *pending* tasks. Offsets refer to positions in `pending`, which is
    /// what the UI shows (SwiftUI `onMove` semantics).
    public mutating func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        var pendingTasks = pending
        let moving = source.sorted().compactMap { pendingTasks.indices.contains($0) ? pendingTasks[$0] : nil }
        guard !moving.isEmpty else { return }
        let insertAt = destination - source.filter { $0 < destination }.count
        pendingTasks = pendingTasks.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        pendingTasks.insert(contentsOf: moving, at: min(max(0, insertAt), pendingTasks.count))
        tasks = tasks.filter { !$0.isPending } + pendingTasks
    }

    /// Sends a pending task to the back of the queue.
    public mutating func skip(id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id && $0.isPending }) else { return }
        let task = tasks.remove(at: index)
        tasks.append(task)
    }

    // MARK: - Recording progress

    public mutating func setOutcome(_ outcome: TaskOutcome, for id: String, at date: Date? = nil) {
        update(id) {
            $0.outcome = outcome
            $0.completedAt = outcome == .completed ? (date ?? $0.completedAt) : nil
        }
    }

    public mutating func recordFocus(id: String, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        update(id) { $0.focusSeconds += seconds }
    }

    public mutating func recordPomodoro(id: String) {
        update(id) { $0.completedPomodoros += 1 }
    }

    /// Copies fresh details (title, notes, project) from Things.
    public mutating func refresh(from todo: ThingsTodo) {
        update(todo.id) {
            $0.title = todo.title
            $0.notes = todo.notes
            $0.context = todo.context
        }
    }

    private mutating func update(_ id: String, _ change: (inout PlannedTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
    }
}

/// One wrapped-up day, kept in the journal.
public struct JournalEntry: Codable, Equatable, Identifiable, Sendable {
    public var day: DayKey
    public var completedTitles: [String]
    public var unfinishedTitles: [String]
    public var pomodoros: Int
    public var focusSeconds: TimeInterval
    public var reflection: String
    public var endedAt: Date

    public var id: DayKey { day }

    public init(day: DayKey, completedTitles: [String], unfinishedTitles: [String], pomodoros: Int, focusSeconds: TimeInterval, reflection: String, endedAt: Date) {
        self.day = day
        self.completedTitles = completedTitles
        self.unfinishedTitles = unfinishedTitles
        self.pomodoros = pomodoros
        self.focusSeconds = focusSeconds
        self.reflection = reflection
        self.endedAt = endedAt
    }
}
