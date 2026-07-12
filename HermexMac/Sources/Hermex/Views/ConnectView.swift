import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var appState: AppState
    @State private var urlText = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                Text("Hermex for Mac")
                    .font(.largeTitle.weight(.semibold))
                Text("Connect to your self-hosted hermes-webui server.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Server URL (https://hermes.example.com)", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(connect)
                SecureField("Server password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)

                if let error = appState.connectionError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack {
                    Spacer()
                    if appState.phase == .connecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Button("Connect", action: connect)
                        .keyboardShortcut(.defaultAction)
                        .disabled(appState.phase == .connecting || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: 420)

            Text("Your Mac talks only to your server — no middleman, no analytics.")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            Spacer()
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            urlText = appState.serverURLString
            password = appState.savedPassword ?? ""
        }
    }

    private func connect() {
        let url = urlText
        let pass = password
        Task {
            await appState.connect(urlString: url, password: pass)
        }
    }
}
