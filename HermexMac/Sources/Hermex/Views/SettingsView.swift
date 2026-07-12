import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Server") {
                    Text(appState.serverURLString.isEmpty ? "Not configured" : appState.serverURLString)
                        .textSelection(.enabled)
                }
                LabeledContent("Status") {
                    switch appState.phase {
                    case .connected:
                        Label("Connected", systemImage: "circle.fill")
                            .foregroundStyle(.green)
                    case .connecting:
                        Label("Connecting…", systemImage: "circle.fill")
                            .foregroundStyle(.orange)
                    case .disconnected:
                        Label("Disconnected", systemImage: "circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                if appState.phase == .connected {
                    Button("Disconnect") {
                        appState.disconnect()
                    }
                }
            } header: {
                Text("Connection")
            }

            Section {
                LabeledContent("Version", value: appVersion)
                Link("Hermex for Mac on GitHub", destination: URL(string: "https://github.com/NicoMancinelli/SJU")!)
                Link("Hermex for iOS (upstream)", destination: URL(string: "https://github.com/uzairansaruzi/hermex")!)
                Link("hermes-webui server", destination: URL(string: "https://github.com/nesquena/hermes-webui")!)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .navigationTitle("Hermex Settings")
    }
}
