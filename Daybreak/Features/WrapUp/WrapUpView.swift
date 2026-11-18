import DaybreakCore
import SwiftUI

struct WrapUpView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [String: ThingsDestination] = [:]
    @State private var reflection = ""

    private var plan: DayPlan { model.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if plan.phase != .active {
                ContentUnavailableView("No day to wrap up", systemImage: "moon.stars",
                                       description: Text("Begin a day first, then wrap it up here."))
            } else {
                content
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    @ViewBuilder private var content: some View {
        Text(plan.day == model.today ? "Wrap up today" : "Wrap up \(plan.day.rawValue)")
            .font(.title2.bold())

        HStack(spacing: 28) {
            Stat(value: "\(plan.completed.count)/\(plan.completed.count + plan.pending.count)", label: "tasks done")
            Stat(value: "\(plan.totalPomodoros)", label: "pomodoros")
            Stat(value: Format.duration(plan.totalFocusSeconds), label: "focused")
        }

        if !plan.completed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Done").font(.headline)
                ForEach(plan.completed) { task in
                    Label {
                        HStack {
                            Text(task.title)
                            Spacer()
                            Text("\(task.completedPomodoros)/\(task.estimate) 🍅")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
        }

        if !plan.pending.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Not finished").font(.headline)
                Text("These go back to Anytime in Things, ready to be picked again. Nothing becomes overdue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(plan.pending) { task in
                    HStack {
                        Text(task.title).lineLimit(1)
                        Spacer()
                        Picker("Send to", selection: binding(for: task.id)) {
                            ForEach([ThingsDestination.anytime, .tomorrow, .someday], id: \.self) { destination in
                                Text(destination.displayName).tag(destination)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("How did today go?").font(.headline)
            TextField("One line for your journal", text: $reflection, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }

        if let error = model.errorMessage {
            ErrorBanner(message: error) { model.errorMessage = nil }
        }

        HStack {
            Spacer()
            Button("Not yet") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("End Day") {
                Task {
                    await model.endDay(destinations: destinations, reflection: reflection)
                    if model.errorMessage == nil { dismiss() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
    }

    private func binding(for id: String) -> Binding<ThingsDestination> {
        Binding(
            get: { destinations[id] ?? .anytime },
            set: { destinations[id] = $0 }
        )
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
