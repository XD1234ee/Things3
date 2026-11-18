import Foundation

/// An in-memory Things for tests and SwiftUI previews. It behaves like Things where it
/// matters: Anytime includes Today, and completed to-dos leave every list.
public actor FakeThingsClient: ThingsClient {
    public private(set) var todosByID: [String: ThingsTodo] = [:]
    public private(set) var listByID: [String: ThingsList] = [:]
    public private(set) var calls: [String] = []
    private var order: [String] = []
    private var nextError: ThingsError?

    public init(_ items: [(ThingsTodo, ThingsList)] = []) {
        for (todo, list) in items {
            todosByID[todo.id] = todo
            listByID[todo.id] = list
            order.append(todo.id)
        }
    }

    /// Makes the next write (complete or move) throw `error`.
    public func failNextWrite(with error: ThingsError) {
        nextError = error
    }

    public func list(of id: String) -> ThingsList? { listByID[id] }

    /// Simulates the user changing a to-do directly in Things.
    public func externallyUpdate(_ todo: ThingsTodo) {
        if todosByID[todo.id] == nil { order.append(todo.id) }
        todosByID[todo.id] = todo
    }

    public func externallyDelete(id: String) {
        todosByID[id] = nil
        listByID[id] = nil
        order.removeAll { $0 == id }
    }

    public func fetch(lists: [ThingsList]) async throws -> [ThingsList: [ThingsTodo]] {
        calls.append("fetch:" + lists.map(\.rawValue).joined(separator: ","))
        var result: [ThingsList: [ThingsTodo]] = [:]
        for list in lists {
            result[list] = order.compactMap { id -> ThingsTodo? in
                guard let todo = todosByID[id], todo.status == .open, let home = listByID[id] else { return nil }
                let matches = home == list || (list == .anytime && home == .today)
                return matches ? todo : nil
            }
        }
        return result
    }

    public func todos(ids: [String]) async throws -> [String: ThingsTodo] {
        calls.append("get:" + ids.joined(separator: ","))
        var result: [String: ThingsTodo] = [:]
        for id in ids { result[id] = todosByID[id] }
        return result
    }

    public func complete(id: String) async throws {
        calls.append("complete:\(id)")
        try throwIfNeeded()
        guard todosByID[id] != nil else { throw ThingsError.scriptFailed("No to-do with id \(id)") }
        todosByID[id]?.status = .completed
    }

    public func move(id: String, to destination: ThingsDestination) async throws {
        calls.append("move:\(id):\(destination.rawValue)")
        try throwIfNeeded()
        guard todosByID[id] != nil else { throw ThingsError.scriptFailed("No to-do with id \(id)") }
        switch destination {
        case .today: listByID[id] = .today
        case .anytime: listByID[id] = .anytime
        case .someday: listByID[id] = .someday
        case .tomorrow: listByID[id] = .upcoming
        }
    }

    private func throwIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}
