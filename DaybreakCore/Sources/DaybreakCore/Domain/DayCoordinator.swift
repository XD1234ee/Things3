import Foundation

/// Applies plan changes that also need a change in Things. Each method writes to Things
/// first and returns the updated plan only if that worked, so the two stay in step.
public struct DayCoordinator: Sendable {
    public let things: ThingsClient

    public init(things: ThingsClient) {
        self.things = things
    }

    /// Commits the plan: puts every planned task in Things Today and starts the day.
    public func beginDay(_ plan: DayPlan, alreadyInToday: Set<String>, now: Date) async throws -> DayPlan {
        for task in plan.pending where !alreadyInToday.contains(task.id) {
            try await things.move(id: task.id, to: .today)
        }
        var plan = plan
        plan.phase = .active
        plan.begunAt = now
        return plan
    }

    /// Adds a task to a day that's already begun.
    public func addDuringDay(_ todo: ThingsTodo, to plan: DayPlan, alreadyInToday: Bool) async throws -> DayPlan {
        var plan = plan
        guard !plan.contains(todo.id) else { return plan }
        if plan.phase == .active && !alreadyInToday {
            try await things.move(id: todo.id, to: .today)
        }
        plan.add(todo)
        return plan
    }

    public func complete(_ id: String, in plan: DayPlan, now: Date) async throws -> DayPlan {
        try await things.complete(id: id)
        var plan = plan
        plan.setOutcome(.completed, for: id, at: now)
        return plan
    }

    /// Moves a task out of today's plan, to Tomorrow or Someday in Things.
    public func postpone(_ id: String, to destination: ThingsDestination, in plan: DayPlan) async throws -> DayPlan {
        try await things.move(id: id, to: destination)
        var plan = plan
        plan.setOutcome(Self.outcome(for: destination), for: id)
        return plan
    }

    public struct EndDayResult: Sendable {
        public var plan: DayPlan
        public var entry: JournalEntry
        /// Tasks that couldn't be moved in Things, with the error message. They stay pending.
        public var failures: [String: String]
    }

    /// Wraps up the day. Unfinished tasks go back to Anytime unless `destinations` says otherwise.
    public func endDay(
        _ plan: DayPlan,
        destinations: [String: ThingsDestination] = [:],
        reflection: String,
        now: Date
    ) async -> EndDayResult {
        var plan = plan
        var failures: [String: String] = [:]
        let unfinishedTitles = plan.pending.map(\.title)

        for task in plan.pending {
            let destination = destinations[task.id] ?? .anytime
            do {
                try await things.move(id: task.id, to: destination)
                plan.setOutcome(Self.outcome(for: destination), for: task.id)
            } catch {
                failures[task.id] = error.localizedDescription
            }
        }

        plan.phase = .ended
        plan.endedAt = now
        let entry = JournalEntry(
            day: plan.day,
            completedTitles: plan.completed.map(\.title),
            unfinishedTitles: unfinishedTitles,
            pomodoros: plan.totalPomodoros,
            focusSeconds: plan.totalFocusSeconds,
            reflection: reflection.trimmingCharacters(in: .whitespacesAndNewlines),
            endedAt: now
        )
        return EndDayResult(plan: plan, entry: entry, failures: failures)
    }

    public enum Change: Equatable, Sendable {
        case completedInThings
        case removedInThings
        case refreshed(ThingsTodo)
    }

    /// Checks pending tasks against Things, to catch changes made there directly.
    /// Returns changes rather than a new plan, so the caller can apply them to its latest copy.
    public func reconcile(_ plan: DayPlan) async throws -> [String: Change] {
        let ids = plan.pending.map(\.id)
        guard !ids.isEmpty else { return [:] }
        let found = try await things.todos(ids: ids)
        var changes: [String: Change] = [:]
        for id in ids {
            guard let todo = found[id] else {
                changes[id] = .removedInThings
                continue
            }
            switch todo.status {
            case .completed: changes[id] = .completedInThings
            case .canceled: changes[id] = .removedInThings
            case .open: changes[id] = .refreshed(todo)
            }
        }
        return changes
    }

    static func outcome(for destination: ThingsDestination) -> TaskOutcome {
        switch destination {
        case .tomorrow: return .postponedTomorrow
        case .someday: return .postponedSomeday
        case .anytime: return .returnedToAnytime
        case .today: return .pending
        }
    }
}

public extension DayPlan {
    mutating func apply(_ changes: [String: DayCoordinator.Change], now: Date) {
        for (id, change) in changes {
            guard task(id)?.isPending == true else { continue }
            switch change {
            case .completedInThings: setOutcome(.completed, for: id, at: now)
            case .removedInThings: setOutcome(.removedInThings, for: id)
            case .refreshed(let todo): refresh(from: todo)
            }
        }
    }
}
