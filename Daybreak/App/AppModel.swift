import AppKit
import DaybreakCore
import KeyboardShortcuts
import SwiftUI

/// The app's single source of state. Views read from it and call its actions.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var engine: PomodoroEngine
    @Published private(set) var ideaSections: [IdeaSection] = []
    @Published private(set) var isLoadingIdeas = false
    @Published private(set) var isBusy = false
    @Published private(set) var now = Date()
    @Published var searchText = "" {
        didSet { rebuildIdeas() }
    }
    @Published var errorMessage: String?
    @Published private(set) var connectionStatus: String?

    /// Set by a SwiftUI view so non-view code (the focus panel, the hotkey) can open windows.
    var openWindowAction: OpenWindowAction?

    let things: ThingsClient
    private let coordinator: DayCoordinator
    private let store: JSONFileStore<AppState>?
    private let notifier = Notifier()
    private var fetchedLists: [ThingsList: [ThingsTodo]] = [:]
    private var timer: Timer?
    private var lastTick = Date()
    private var lastSave = Date()
    private var lastReconcile = Date.distantPast
    private(set) lazy var focusPanel = FocusPanelController(model: self)

    init(things: ThingsClient, store: JSONFileStore<AppState>?) {
        self.things = things
        self.coordinator = DayCoordinator(things: things)
        self.store = store
        let today = DayKey(Date())
        var loaded = (try? store?.load()) ?? AppState.initial(today: today)
        loaded.rollOver(to: today)
        self.state = loaded
        self.engine = PomodoroEngine(settings: loaded.settings.pomodoro)
        startTimer()
        KeyboardShortcuts.onKeyUp(for: .toggleFocusPanel) { [weak self] in
            Task { @MainActor in self?.focusPanel.toggle() }
        }
        notifier.requestAuthorization()
    }

    static func live() -> AppModel {
        let store = (try? AppPaths.stateFile()).map { JSONFileStore<AppState>(url: $0) }
        return AppModel(things: AppleScriptThingsClient(), store: store)
    }

    // MARK: - Derived state

    var plan: DayPlan { state.plan }
    var settings: AppSettings { state.settings }
    var today: DayKey { DayKey(now) }
    var hasUnfinishedPreviousDay: Bool { state.hasUnfinishedPreviousDay(today: today) }
    var currentTask: PlannedTask? { plan.phase == .active ? plan.current : nil }

    var availablePomodoros: Int {
        Capacity.pomodorosThatFit(now: now, workdayEnd: settings.workdayEnd, settings: settings.pomodoro)
    }

    var timerText: String {
        let seconds = Int(engine.remaining(at: now).rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var phaseProgress: Double { engine.progress(at: now) }

    var menuBarTitle: String {
        if hasUnfinishedPreviousDay { return "Wrap up" }
        switch plan.phase {
        case .planning: return "Plan"
        case .ended: return "Done"
        case .active:
            if engine.phase.isBreak { return "Break \(timerText)" }
            guard let task = plan.current else { return "All done" }
            let title = task.title.count > 24 ? String(task.title.prefix(23)) + "…" : task.title
            return engine.phase == .focus ? "\(timerText) · \(title)" : title
        }
    }

    var menuBarSymbol: String {
        switch plan.phase {
        case .planning: return "sunrise"
        case .ended: return "moon.stars"
        case .active: return engine.phase.isBreak ? "cup.and.saucer" : "scope"
        }
    }

    // MARK: - Ideas

    func refreshIdeas() async {
        isLoadingIdeas = true
        defer { isLoadingIdeas = false }
        do {
            fetchedLists = try await things.fetch(lists: IdeaPool.sourceLists)
            rebuildIdeas()
        } catch {
            report(error)
        }
    }

    private func rebuildIdeas() {
        ideaSections = IdeaPool.build(from: fetchedLists, now: now, search: searchText)
    }

    private var idsInThingsToday: Set<String> {
        Set((fetchedLists[.today] ?? []).map(\.id))
    }

    // MARK: - Planning

    func add(_ todo: ThingsTodo) {
        guard !plan.contains(todo.id) else { return }
        if plan.phase == .active {
            perform { [self] in
                state.plan = try await coordinator.addDuringDay(todo, to: plan, alreadyInToday: idsInThingsToday.contains(todo.id))
            }
        } else {
            state.plan.add(todo)
            save()
        }
    }

    func remove(_ id: String) {
        state.plan.remove(id: id)
        save()
    }

    func setEstimate(_ id: String, to value: Int) {
        state.plan.setEstimate(id: id, to: value)
        save()
    }

    func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        state.plan.movePending(fromOffsets: source, toOffset: destination)
        save()
    }

    func beginDay() {
        perform { [self] in
            state.plan = try await coordinator.beginDay(plan, alreadyInToday: idsInThingsToday, now: Date())
            save()
            focusPanel.show()
        }
    }

    func startNewPlan() {
        engine.stop()
        state.plan = .empty(for: today)
        save()
    }

    // MARK: - Focus

    func startFocus() {
        engine.startFocus(at: Date())
        lastTick = Date()
    }

    func togglePause() {
        let now = Date()
        if engine.isPaused { engine.resume(at: now) } else { engine.pause(at: now) }
        lastTick = now
    }

    func skipBreak() {
        engine.skipBreak()
    }

    func stopFocus() {
        engine.stop()
    }

    func completeCurrent() {
        guard let task = currentTask else { return }
        perform { [self] in
            state.plan = try await coordinator.complete(task.id, in: plan, now: Date())
            save()
            NSSound(named: "Pop")?.play()
            if plan.current == nil {
                engine.stop()
                notifier.post(title: "Everything planned is done", body: "Nice work. Wrap up the day when you're ready.")
            }
        }
    }

    func skipCurrent() {
        guard let task = currentTask else { return }
        state.plan.skip(id: task.id)
        save()
    }

    func postponeCurrent(to destination: ThingsDestination) {
        guard let task = currentTask else { return }
        perform { [self] in
            state.plan = try await coordinator.postpone(task.id, to: destination, in: plan)
            save()
        }
    }

    func openInThings(_ id: String) {
        guard let url = ThingsLinks.show(id: id) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Wrap-up

    func endDay(destinations: [String: ThingsDestination], reflection: String) async {
        isBusy = true
        defer { isBusy = false }
        let result = await coordinator.endDay(plan, destinations: destinations, reflection: reflection, now: Date())
        state.plan = result.plan
        state.addToJournal(result.entry)
        engine.stop()
        focusPanel.hide()
        if !result.failures.isEmpty {
            errorMessage = "Some tasks couldn't be moved in Things: " + result.failures.values.joined(separator: "; ")
        }
        state.rollOver(to: today)
        save()
    }

    // MARK: - Windows

    func open(_ window: WindowID) {
        openWindowAction?.callAsFunction(id: window.rawValue)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&state.settings)
        engine.settings = state.settings.pomodoro
        save()
    }

    func testConnection() async {
        connectionStatus = "Checking…"
        do {
            if let client = things as? AppleScriptThingsClient {
                let version = try await client.ping()
                connectionStatus = "Connected to Things \(version ?? "")."
            } else {
                _ = try await things.fetch(lists: [.today])
                connectionStatus = "Connected."
            }
        } catch {
            connectionStatus = error.localizedDescription
        }
    }

    // MARK: - Timer

    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let current = Date()
        let elapsed = current.timeIntervalSince(lastTick)
        lastTick = current
        now = current

        // Credit focus time to whichever task is current; ignore gaps from sleep.
        if engine.isFocusRunning, let id = currentTask?.id, elapsed > 0, elapsed < 5 {
            state.plan.recordFocus(id: id, seconds: elapsed)
        }

        if let event = engine.tick(at: current) {
            handle(event)
        }

        if plan.phase == .active, current.timeIntervalSince(lastReconcile) > 60 {
            lastReconcile = current
            Task { await reconcile() }
        }

        let previousDay = plan.day
        state.rollOver(to: today)
        if plan.day != previousDay || current.timeIntervalSince(lastSave) > 30 {
            save()
        }
    }

    private func handle(_ event: PomodoroEvent) {
        switch event {
        case .focusCompleted(_, let nextBreak):
            if let id = currentTask?.id { state.plan.recordPomodoro(id: id) }
            save()
            NSSound(named: "Glass")?.play()
            let minutes = nextBreak == .longBreak ? settings.pomodoro.longBreakMinutes : settings.pomodoro.shortBreakMinutes
            notifier.post(title: "Pomodoro done 🍅", body: "Take a \(minutes)-minute break.")
        case .breakCompleted:
            NSSound(named: "Purr")?.play()
            notifier.post(title: "Break's over", body: currentTask.map { "Next: \($0.title)" } ?? "Ready when you are.")
        }
    }

    private func reconcile() async {
        do {
            let changes = try await coordinator.reconcile(plan)
            state.plan.apply(changes, now: Date())
        } catch {
            // Reconciliation is best-effort; don't interrupt the user for it.
        }
    }

    // MARK: - Helpers

    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            isBusy = true
            defer { isBusy = false }
            do {
                try await work()
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func save() {
        lastSave = Date()
        do {
            try store?.save(state)
        } catch {
            report(error)
        }
    }
}

enum WindowID: String {
    case planner, wrapUp
}

extension KeyboardShortcuts.Name {
    static let toggleFocusPanel = Self("toggleFocusPanel", default: .init(.space, modifiers: [.option]))
}
