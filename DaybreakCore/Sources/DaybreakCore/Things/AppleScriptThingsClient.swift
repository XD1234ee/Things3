import Foundation

/// Talks to Things 3 by running `things.js` through `/usr/bin/osascript`.
///
/// Arguments are passed as argv (never spliced into script source), so titles and
/// IDs can't inject script code.
public struct AppleScriptThingsClient: ThingsClient {
    public let scriptURL: URL
    public let timeout: TimeInterval
    private let runner: ScriptRunner

    public init(scriptURL: URL = ThingsBridgeScript.url, timeout: TimeInterval = 20) {
        self.scriptURL = scriptURL
        self.timeout = timeout
        self.runner = ScriptRunner(executable: URL(fileURLWithPath: "/usr/bin/osascript"))
    }

    public func ping() async throws -> String? {
        let data = try await run(["ping"])
        let reply = try ThingsBridgeDecoding.decode(PingReply.self, from: data)
        return reply.version
    }

    public func fetch(lists: [ThingsList]) async throws -> [ThingsList: [ThingsTodo]] {
        guard !lists.isEmpty else { return [:] }
        let data = try await run(["lists"] + lists.map(\.rawValue))
        return try ThingsBridgeDecoding.decodeLists(data)
    }

    public func todos(ids: [String]) async throws -> [String: ThingsTodo] {
        guard !ids.isEmpty else { return [:] }
        let data = try await run(["get"] + ids)
        return try ThingsBridgeDecoding.decodeLookup(data)
    }

    public func complete(id: String) async throws {
        _ = try await run(["complete", id])
    }

    public func move(id: String, to destination: ThingsDestination) async throws {
        _ = try await run(["move", id, destination.rawValue])
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let result = try await runner.run(
            arguments: ["-l", "JavaScript", scriptURL.path] + arguments,
            timeout: timeout
        )
        if result.timedOut { throw ThingsError.timeout }
        guard result.exitCode == 0 else {
            throw ThingsBridgeDecoding.error(fromStderr: result.stderr)
        }
        return result.stdout
    }

    private struct PingReply: Decodable {
        let ok: Bool
        let version: String?
    }
}

public enum ThingsBridgeScript {
    /// The bundled `things.js`.
    public static var url: URL {
        guard let url = Bundle.module.url(forResource: "things", withExtension: "js") else {
            fatalError("things.js is missing from the DaybreakCore bundle")
        }
        return url
    }
}

/// Turns `things.js` output into model types. Separate from the client so it can be tested.
public enum ThingsBridgeDecoding {
    struct RawTodo: Decodable {
        let id: String
        let name: String
        let notes: String?
        let status: String?
        let deadline: String?
        let startDate: String?
        let tags: String?
        let project: String?
        let area: String?

        var todo: ThingsTodo {
            ThingsTodo(
                id: id,
                title: name,
                notes: notes ?? "",
                status: ThingsStatus(rawValue: status ?? "open") ?? .open,
                projectName: project.flatMap { $0.isEmpty ? nil : $0 },
                areaName: area.flatMap { $0.isEmpty ? nil : $0 },
                tags: (tags ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                deadline: deadline.flatMap(parseDate),
                startDate: startDate.flatMap(parseDate)
            )
        }
    }

    public static func decodeLists(_ data: Data) throws -> [ThingsList: [ThingsTodo]] {
        let raw = try decode([String: [RawTodo]].self, from: data)
        var result: [ThingsList: [ThingsTodo]] = [:]
        for (key, items) in raw {
            guard let list = ThingsList(rawValue: key) else { continue }
            result[list] = items.map(\.todo)
        }
        return result
    }

    public static func decodeLookup(_ data: Data) throws -> [String: ThingsTodo] {
        let raw = try decode([String: RawTodo?].self, from: data)
        return raw.compactMapValues { $0?.todo }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(decoding: data.prefix(200), as: UTF8.self)
            throw ThingsError.badOutput("\(error.localizedDescription) — \(preview)")
        }
    }

    /// JavaScript's `toISOString()` always includes milliseconds.
    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    public static func error(fromStderr stderr: String) -> ThingsError {
        // osascript reports Apple event errors with their numeric codes.
        if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") {
            return .permissionDenied
        }
        if stderr.contains("-2700") && stderr.contains("Application can't be found")
            || stderr.localizedCaseInsensitiveContains("can't get application")
            || stderr.localizedCaseInsensitiveContains("application can't be found") {
            return .notInstalled
        }
        if stderr.contains("-1712") { return .timeout }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .scriptFailed(message.isEmpty ? "unknown error" : message)
    }
}
