import DaybreakCore
import SwiftUI

@main
struct DaybreakApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Plan Your Day", id: WindowID.planner.rawValue) {
            PlannerView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 920, height: 620)

        Window("Wrap Up", id: WindowID.wrapUp.rawValue) {
            WrapUpView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.menuBarSymbol)
            Text(model.menuBarTitle)
                .monospacedDigit()
        }
        .onAppear { model.openWindowAction = openWindow }
    }
}
