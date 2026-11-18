import Foundation

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// A long break follows every Nth pomodoro.
    public var longBreakEvery: Int

    public init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15, longBreakEvery: Int = 4) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.longBreakEvery = longBreakEvery
    }

    public var focus: TimeInterval { TimeInterval(max(1, focusMinutes) * 60) }
    public var shortBreak: TimeInterval { TimeInterval(max(1, shortBreakMinutes) * 60) }
    public var longBreak: TimeInterval { TimeInterval(max(1, longBreakMinutes) * 60) }

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .idle, .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

public enum PomodoroPhase: String, Codable, Sendable {
    case idle, focus, shortBreak, longBreak

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

public enum PomodoroEvent: Equatable, Sendable {
    /// A focus period ran to the end. `count` is the number of pomodoros completed this session.
    case focusCompleted(count: Int, nextBreak: PomodoroPhase)
    case breakCompleted
}

/// A Pomodoro timer as a value type. Time is always passed in, so it's deterministic to test.
///
/// Flow: idle → focus → (short or long) break → idle → focus …
/// A break starts automatically when a focus period ends; the next focus period starts
/// when the user asks for it. Completing a *task* doesn't touch the timer: the next task
/// simply takes over the rest of the current pomodoro.
public struct PomodoroEngine: Equatable, Sendable {
    public var settings: PomodoroSettings
    public private(set) var phase: PomodoroPhase = .idle
    public private(set) var completedFocusCount = 0
    private var endsAt: Date?
    private var pausedRemaining: TimeInterval?

    public init(settings: PomodoroSettings = PomodoroSettings()) {
        self.settings = settings
    }

    public var isPaused: Bool { pausedRemaining != nil }
    public var isFocusRunning: Bool { phase == .focus && !isPaused }

    /// Length of the current (or, when idle, the next) phase.
    public var phaseDuration: TimeInterval { settings.duration(of: phase) }

    public func remaining(at now: Date) -> TimeInterval {
        if let paused = pausedRemaining { return paused }
        guard let endsAt else { return phaseDuration }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// 0 at the start of the phase, 1 at the end.
    public func progress(at now: Date) -> Double {
        guard phase != .idle else { return 0 }
        let duration = phaseDuration
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    public mutating func startFocus(at now: Date) {
        phase = .focus
        endsAt = now.addingTimeInterval(settings.focus)
        pausedRemaining = nil
    }

    public mutating func pause(at now: Date) {
        guard phase != .idle, pausedRemaining == nil else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    public mutating func resume(at now: Date) {
        guard let paused = pausedRemaining else { return }
        endsAt = now.addingTimeInterval(paused)
        pausedRemaining = nil
    }

    public mutating func skipBreak() {
        guard phase.isBreak else { return }
        reset()
    }

    /// Abandons the current phase without counting it.
    public mutating func stop() {
        reset()
    }

    /// Call regularly (e.g. every second). Returns an event when a phase ends.
    @discardableResult
    public mutating func tick(at now: Date) -> PomodoroEvent? {
        guard phase != .idle, pausedRemaining == nil, let endsAt, now >= endsAt else { return nil }
        switch phase {
        case .focus:
            completedFocusCount += 1
            let every = max(1, settings.longBreakEvery)
            let next: PomodoroPhase = completedFocusCount % every == 0 ? .longBreak : .shortBreak
            phase = next
            self.endsAt = now.addingTimeInterval(settings.duration(of: next))
            return .focusCompleted(count: completedFocusCount, nextBreak: next)
        case .shortBreak, .longBreak:
            reset()
            return .breakCompleted
        case .idle:
            return nil
        }
    }

    private mutating func reset() {
        phase = .idle
        endsAt = nil
        pausedRemaining = nil
    }
}

public enum Capacity {
    /// How many pomodoros (each followed by its break) fit between `now` and the end of the workday.
    public static func pomodorosThatFit(
        now: Date,
        workdayEnd: DateComponents,
        settings: PomodoroSettings,
        calendar: Calendar = .current
    ) -> Int {
        guard let end = calendar.date(
            bySettingHour: workdayEnd.hour ?? 18,
            minute: workdayEnd.minute ?? 0,
            second: 0,
            of: now
        ) else { return 0 }
        var available = end.timeIntervalSince(now)
        var count = 0
        while available >= settings.focus {
            available -= settings.focus
            count += 1
            available -= count % max(1, settings.longBreakEvery) == 0 ? settings.longBreak : settings.shortBreak
        }
        return count
    }
}
