import AppKit
import DaybreakCore
import SwiftUI

/// A small always-on-top panel showing the one task you're working on.
@MainActor
final class FocusPanelController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Focus"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        if let model {
            let host = NSHostingController(rootView: FocusView().environmentObject(model))
            host.sizingOptions = [.preferredContentSize]
            panel.contentViewController = host
        }

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 380, y: screen.maxY - 260))
        }
        return panel
    }
}

struct FocusView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.hasUnfinishedPreviousDay || model.plan.phase != .active {
                idle
            } else if model.engine.phase.isBreak {
                onBreak
            } else if let task = model.plan.current {
                focus(on: task)
            } else {
                allDone
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 16)
        .frame(width: 360, alignment: .leading)
    }

    private func focus(on task: PlannedTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(task.context ?? "Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PomodoroDots(done: task.completedPomodoros, estimate: task.estimate)
            }

            Text(task.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !task.notes.isEmpty {
                ScrollView {
                    Text(task.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 72)
            }

            HStack(alignment: .center) {
                Text(model.timerText)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.engine.phase == .focus ? .primary : .secondary)
                Spacer()
                TimerButton()
            }
            ProgressView(value: model.phaseProgress)
                .opacity(model.engine.phase == .idle ? 0 : 1)

            HStack {
                Button { model.completeCurrent() } label: { Label("Done", systemImage: "checkmark") }
                    .keyboardShortcut(.return, modifiers: .command)
                Button { model.skipCurrent() } label: { Label("Later", systemImage: "arrow.uturn.down") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(model.plan.upNext.isEmpty)
                    .help("Move to the end of today's plan")
                Menu {
                    Button("Tomorrow") { model.postponeCurrent(to: .tomorrow) }
                    Button("Someday") { model.postponeCurrent(to: .someday) }
                } label: {
                    Label("Postpone", systemImage: "calendar")
                }
                .fixedSize()
                Spacer()
                Button { model.openInThings(task.id) } label: { Image(systemName: "arrow.up.forward.app") }
                    .keyboardShortcut("o")
                    .help("Open in Things")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)

            if let next = model.plan.upNext.first {
                Text("Next: \(next.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }
        }
    }

    private var onBreak: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.engine.phase == .longBreak ? "Long break" : "Short break")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Step away for a moment.")
                .font(.title3.weight(.semibold))
            HStack {
                Text(model.timerText)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer()
                TimerButton()
            }
            ProgressView(value: model.phaseProgress)
            if let next = model.plan.current {
                Text("Next: \(next.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var allDone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everything planned is done 🎉")
                .font(.title3.weight(.semibold))
            Text("\(model.plan.totalPomodoros) 🍅 · \(Format.duration(model.plan.totalFocusSeconds)) focused")
                .foregroundStyle(.secondary)
            HStack {
                Button("Add more") { model.open(.planner) }
                Button("Wrap up the day") { model.open(.wrapUp) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No day in progress")
                .font(.title3.weight(.semibold))
            Button("Plan your day") { model.open(.planner) }
                .buttonStyle(.borderedProminent)
        }
    }
}
