import DaybreakCore
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.now.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.hasUnfinishedPreviousDay {
                Text("Yesterday's plan is still open.")
                    .font(.headline)
                Button("Wrap up yesterday") { model.open(.wrapUp) }
                    .buttonStyle(.borderedProminent)
            } else {
                switch model.plan.phase {
                case .planning: planning
                case .active: active
                case .ended: ended
                }
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { model.openWindowAction = openWindow }
    }

    @ViewBuilder private var planning: some View {
        Text(model.plan.tasks.isEmpty ? "Your day is empty." : "\(model.plan.tasks.count) tasks picked, not started.")
            .font(.headline)
        Text("Choose a few things that will make today a good day.")
            .font(.callout)
            .foregroundStyle(.secondary)
        Button("Plan your day") { model.open(.planner) }
            .buttonStyle(.borderedProminent)
    }

    @ViewBuilder private var active: some View {
        if let task = model.plan.current {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.engine.phase.isBreak ? "On a break" : "Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack {
                    PomodoroDots(done: task.completedPomodoros, estimate: task.estimate)
                    Spacer()
                    if model.engine.phase != .idle {
                        Text(model.timerText).monospacedDigit()
                    }
                }
            }
            HStack {
                TimerButton()
                Button("Done") { model.completeCurrent() }
            }
            if !model.plan.upNext.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(model.plan.upNext.prefix(3)) { next in
                        Text("• " + next.title).font(.callout).lineLimit(1)
                    }
                }
            }
        } else {
            Text("Everything planned is done 🎉")
                .font(.headline)
        }
        Divider()
        Button(model.focusPanel.isVisible ? "Hide focus panel" : "Show focus panel") { model.focusPanel.toggle() }
            .buttonStyle(.borderless)
        Button("Edit plan…") { model.open(.planner) }
            .buttonStyle(.borderless)
        Button("End day…") { model.open(.wrapUp) }
            .buttonStyle(.borderless)
    }

    @ViewBuilder private var ended: some View {
        Text("Day wrapped up.")
            .font(.headline)
        Text("\(model.plan.completed.count) done · \(model.plan.totalPomodoros) 🍅 · \(Format.duration(model.plan.totalFocusSeconds)) focused")
            .font(.callout)
            .foregroundStyle(.secondary)
        Button("Start a new plan") {
            model.startNewPlan()
            model.open(.planner)
        }
    }
}

/// Start / pause / resume, depending on the timer's state.
struct TimerButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.engine.phase {
        case .idle:
            Button { model.startFocus() } label: { Label("Start 🍅", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
        case .focus:
            Button { model.togglePause() } label: {
                Label(model.engine.isPaused ? "Resume" : "Pause", systemImage: model.engine.isPaused ? "play.fill" : "pause.fill")
            }
        case .shortBreak, .longBreak:
            Button { model.skipBreak() } label: { Label("Skip break", systemImage: "forward.fill") }
        }
    }
}

struct PomodoroDots: View {
    let done: Int
    let estimate: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(done, estimate), id: \.self) { index in
                Text(index < done ? "🍅" : "○")
                    .font(.caption)
                    .foregroundStyle(index < estimate ? .primary : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(estimate) pomodoros")
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
