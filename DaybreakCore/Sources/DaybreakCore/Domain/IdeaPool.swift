import Foundation

/// A group of candidate to-dos shown while planning.
public struct IdeaSection: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case today, deadlines, inbox, anytime
    }

    public var kind: Kind
    public var todos: [ThingsTodo]

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .today: return "In Things Today"
        case .deadlines: return "Deadlines soon"
        case .inbox: return "Inbox"
        case .anytime: return "Anytime"
        }
    }
}

/// Builds the planner's idea pool from Things lists. Each to-do appears once, in the
/// first section that fits: Today → Deadlines → Inbox → Anytime.
public enum IdeaPool {
    public static let sourceLists: [ThingsList] = [.today, .inbox, .anytime, .upcoming]

    public static func build(
        from lists: [ThingsList: [ThingsTodo]],
        now: Date,
        deadlineWindowDays: Int = 3,
        search: String = "",
        calendar: Calendar = .current
    ) -> [IdeaSection] {
        var seen = Set<String>()
        func take(_ todos: [ThingsTodo], where include: (ThingsTodo) -> Bool = { _ in true }) -> [ThingsTodo] {
            todos.filter { todo in
                guard todo.status == .open, !seen.contains(todo.id), include(todo) else { return false }
                seen.insert(todo.id)
                return true
            }
        }

        let startOfToday = calendar.startOfDay(for: now)
        let deadlineLimit = calendar.date(byAdding: .day, value: deadlineWindowDays + 1, to: startOfToday) ?? now
        let everything = (lists[.inbox] ?? []) + (lists[.anytime] ?? []) + (lists[.upcoming] ?? [])

        let today = take(lists[.today] ?? [])
        let deadlines = take(everything) { ($0.deadline ?? .distantFuture) < deadlineLimit }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        let inbox = take(lists[.inbox] ?? [])
        let anytime = take(lists[.anytime] ?? [])

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            IdeaSection(kind: .today, todos: today),
            IdeaSection(kind: .deadlines, todos: deadlines),
            IdeaSection(kind: .inbox, todos: inbox),
            IdeaSection(kind: .anytime, todos: anytime),
        ]
        .map { section in
            guard !query.isEmpty else { return section }
            var filtered = section
            filtered.todos = section.todos.filter { matches($0, query) }
            return filtered
        }
        .filter { !$0.todos.isEmpty }
    }

    static func matches(_ todo: ThingsTodo, _ query: String) -> Bool {
        let haystack = [todo.title, todo.notes, todo.context ?? ""] + todo.tags
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
