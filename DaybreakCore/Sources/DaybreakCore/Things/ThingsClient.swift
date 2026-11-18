import Foundation

/// Everything Daybreak needs from Things. The app uses `AppleScriptThingsClient`;
/// tests and previews use `FakeThingsClient`.
public protocol ThingsClient: Sendable {
    /// Open to-dos in each requested list, in Things' order.
    /// Note: as in Things, `.anytime` also contains the to-dos that are in Today.
    func fetch(lists: [ThingsList]) async throws -> [ThingsList: [ThingsTodo]]

    /// Looks up to-dos by ID, including completed ones. Missing IDs are absent from the result.
    func todos(ids: [String]) async throws -> [String: ThingsTodo]

    func complete(id: String) async throws

    func move(id: String, to destination: ThingsDestination) async throws
}

public enum ThingsLinks {
    /// `things:///show?id=…`
    public static func show(id: String) -> URL? {
        var components = URLComponents()
        components.scheme = "things"
        components.host = ""
        components.path = "/show"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }
}
