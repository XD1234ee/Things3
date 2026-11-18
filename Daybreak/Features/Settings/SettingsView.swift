import DaybreakCore
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Pomodoro") {
                Stepper(value: setting(\.pomodoro.focusMinutes), in: 5...90, step: 5) {
                    Text("Focus: \(model.settings.pomodoro.focusMinutes) min")
                }
                Stepper(value: setting(\.pomodoro.shortBreakMinutes), in: 1...30) {
                    Text("Short break: \(model.settings.pomodoro.shortBreakMinutes) min")
                }
                Stepper(value: setting(\.pomodoro.longBreakMinutes), in: 5...60, step: 5) {
                    Text("Long break: \(model.settings.pomodoro.longBreakMinutes) min")
                }
                Stepper(value: setting(\.pomodoro.longBreakEvery), in: 2...8) {
                    Text("Long break after every \(model.settings.pomodoro.longBreakEvery) pomodoros")
                }
            }

            Section("Day") {
                DatePicker("Workday ends at", selection: workdayEnd, displayedComponents: .hourAndMinute)
            }

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Show or hide the focus panel:", name: .toggleFocusPanel)
            }

            Section("Things") {
                HStack {
                    Button("Test connection") { Task { await model.testConnection() } }
                    if let status = model.connectionStatus {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Daybreak asks for permission to control Things the first time it reads your lists. You can change this in System Settings → Privacy & Security → Automation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in model.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var workdayEnd: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.settings.workdayEndHour, minute: model.settings.workdayEndMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.updateSettings {
                    $0.workdayEndHour = parts.hour ?? 18
                    $0.workdayEndMinute = parts.minute ?? 0
                }
            }
        )
    }
}
