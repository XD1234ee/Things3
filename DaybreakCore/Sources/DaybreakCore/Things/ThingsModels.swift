import Foundation

/// The built-in Things lists Daybreak reads from.
public enum ThingsList: String, CaseIterable, Codable, Sendable {
    case inbox, today, anytime, upcoming, someday
}

public enum ThingsStatus: String, Codable, Sendable {
    case open, completed, canceled
}

/// Where a to-do can be sent in Things.
public enum ThingsDestination: String, CaseIterable, Codable, Sendable {
    case today, anytime, someday, tomorrow

    public var displayName: String {
        switch self {
        case .today: return "Today"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
        case .tomorrow: return "Tomorrow"
        }
    }
}

/// A Things to-do, as much of it as Daybreak needs.
public struct ThingsTodo: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    public var status: ThingsStatus
    public var projectName: String?
    public var areaName: String?
    public var tags: [String]
    public var deadline: Date?
    public var startDate: Date?

    public init(
        id: String,
        title: String,
        notes: String = "",
        status: ThingsStatus = .open,
        projectName: String? = nil,
        areaName: String? = nil,
        tags: [String] = [],
        deadline: Date? = nil,
        startDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.projectName = projectName
        self.areaName = areaName
        self.tags = tags
        self.deadline = deadline
        self.startDate = startDate
    }

    /// The project, or failing that the area, the to-do belongs to.
    public var context: String? { projectName ?? areaName }
}

public enum ThingsError: Error, Equatable, LocalizedError {
    case notInstalled
    case permissionDenied
    case timeout
    case scriptFailed(String)
    case badOutput(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Things 3 doesn't seem to be installed."
        case .permissionDenied:
            return "Daybreak isn't allowed to control Things. Turn it on in System Settings → Privacy & Security → Automation."
        case .timeout:
            return "Things took too long to respond."
        case .scriptFailed(let message):
            return "Things reported an error: \(message)"
        case .badOutput(let detail):
            return "Couldn't read the response from Things (\(detail))."
        }
    }
}
