import DaybreakCore
import SwiftUI

struct PlannerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            IdeaPoolColumn()
                .frame(minWidth: 340, idealWidth: 420)
            PlanColumn()
                .frame(minWidth: 380, idealWidth: 460)
        }
        .task { await model.refreshIdeas() }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refreshIdeas() }
                } label: {
                    Label("Refresh from Things", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
            }
        }
    }
}

// MARK: - Ideas from Things

private struct IdeaPoolColumn: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Things", text: $model.searchText)
                    .textFieldStyle(.plain)
                if model.isLoadingIdeas { ProgressView().controlSize(.small) }
            }
            .padding(10)
            Divider()

            if model.ideaSections.isEmpty && !model.isLoadingIdeas {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "Nothing in Things yet" : "No matches",
                    systemImage: "tray",
                    description: Text(model.searchText.isEmpty ? "Add to-dos in Things, then refresh." : "Try a different search.")
                )
            } else {
                List {
                    ForEach(model.ideaSections) { section in
                        Section(section.title) {
                            ForEach(section.todos) { todo in
                                IdeaRow(todo: todo, isPlanned: model.plan.contains(todo.id)) {
                                    model.add(todo)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct IdeaRow: View {
    let todo: ThingsTodo
    let isPlanned: Bool
    let add: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: add) {
                Image(systemName: isPlanned ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isPlanned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(isPlanned)
            .accessibilityLabel(isPlanned ? "In today's plan" : "Add to today's plan")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .foregroundStyle(isPlanned ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let context = todo.context { Text(context) }
                    if let deadline = todo.deadline {
                        Label(deadline.formatted(.dateTime.month(.abbreviated).day()), systemImage: "flag.fill")
                            .foregroundStyle(deadline < Calendar.current.startOfDay(for: Date()) ? .red : .orange)
                    }
                    if !todo.tags.isEmpty { Text(todo.tags.map { "#" + $0 }.joined(separator: " ")) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: add)
    }
}

// MARK: - Today's plan

private struct PlanColumn: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.plan.phase == .active ? "Today" : "Today's plan")
                    .font(.title2.bold())
                Text(model.plan.phase == .active
                     ? "Your day has begun. You can still add, reorder or drop tasks."
                     : "What will make today a good day? Pick a few things.")
                    .foregroundStyle(.secondary)
            }

            if model.plan.pending.isEmpty {
                ContentUnavailableView("Nothing planned yet", systemImage: "sunrise", description: Text("Add tasks from the list on the left."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.plan.pending) { task in
                        PlanRow(task: task)
                    }
                    .onMove { model.movePending(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
            }

            CapacityBar(planned: model.plan.remainingPomodoros, available: model.availablePomodoros, settings: model.settings)

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            if model.plan.phase == .planning {
                HoldToBeginButton(isEnabled: !model.plan.pending.isEmpty && !model.isBusy) {
                    model.beginDay()
                    dismiss()
                }
            }
        }
        .padding(16)
    }
}

private struct PlanRow: View {
    @EnvironmentObject private var model: AppModel
    let task: PlannedTask

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(2)
                if let context = task.context {
                    Text(context).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Stepper(value: Binding(get: { task.estimate }, set: { model.setEstimate(task.id, to: $0) }),
                    in: PlannedTask.estimateRange) {
                Text("\(task.estimate) 🍅").monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel("Estimate: \(task.estimate) pomodoros")
            Button { model.remove(task.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove from plan")
        }
        .padding(.vertical, 2)
    }
}

private struct CapacityBar: View {
    let planned: Int
    let available: Int
    let settings: AppSettings

    private var isOver: Bool { planned > available }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(min(planned, max(available, 1))), total: Double(max(available, 1)))
                .tint(isOver ? .orange : .accentColor)
            Text(summary)
                .font(.caption)
                .foregroundStyle(isOver ? .orange : .secondary)
        }
    }

    private var summary: String {
        let end = String(format: "%d:%02d", settings.workdayEndHour, settings.workdayEndMinute)
        if available == 0 { return "\(planned) 🍅 planned · your workday (until \(end)) is over" }
        let base = "\(planned) of \(available) 🍅 that fit before \(end)"
        return isOver ? base + " — that's more than fits" : base
    }
}

/// Press and hold to commit the plan: a small ritual instead of a plain button.
private struct HoldToBeginButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var progress: CGFloat = 0
    private let holdDuration = 0.8

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.accentColor.opacity(isEnabled ? 0.18 : 0.08))
            GeometryReader { proxy in
                Capsule().fill(Color.accentColor).frame(width: proxy.size.width * progress)
            }
            Label("Hold to Begin Day", systemImage: "sunrise.fill")
                .font(.headline)
                .foregroundStyle(progress > 0.5 ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 40)
        .clipShape(Capsule())
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: holdDuration) {
            guard isEnabled else { return }
            action()
            progress = 0
        } onPressingChanged: { pressing in
            guard isEnabled else { return }
            withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.2)) {
                progress = pressing ? 1 : 0
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Begin Day")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { action() } }
    }
}
