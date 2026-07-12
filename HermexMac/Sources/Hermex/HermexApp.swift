import SwiftUI

@main
struct HermexApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    Task { await appState.createSession() }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState.phase != .connected)

                Button("Refresh Sessions") {
                    Task { await appState.refreshSessions() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.phase != .connected)
            }
            CommandGroup(after: .appSettings) {
                Button("Disconnect from Server") {
                    appState.disconnect()
                }
                .disabled(appState.phase != .connected)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.phase == .connected {
                MainView()
            } else {
                ConnectView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}
