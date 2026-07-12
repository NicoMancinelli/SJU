import Foundation
import SwiftUI

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case connected
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: ConnectionPhase = .disconnected
    @Published var serverURLString: String
    @Published var connectionError: String?

    @Published var sessions: [SessionSummary] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false

    @Published var modelOptions: [ModelOption] = []
    @Published var defaultModelID: String?
    @Published var selectedModel: ModelOption?

    @Published var selectedSessionID: String?

    private(set) var client: APIClient?

    private static let serverURLKey = "hermex.serverURL"

    init() {
        serverURLString = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""
    }

    var savedPassword: String? {
        let server = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty else { return nil }
        return KeychainStore.password(forServer: server)
    }

    /// Validates the URL, checks `/health`, and logs in when the server has
    /// auth enabled. On failure, `connectionError` carries a user-readable message.
    func connect(urlString: String, password: String) async {
        connectionError = nil

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed
        if !candidate.lowercased().hasPrefix("http://") && !candidate.lowercased().hasPrefix("https://") {
            candidate = "https://" + candidate
        }
        guard let components = URLComponents(string: candidate),
              let host = components.host, !host.isEmpty,
              let baseURL = components.url
        else {
            connectionError = "Enter a server URL like https://hermes.example.com"
            return
        }

        phase = .connecting
        let client = APIClient(baseURL: baseURL)

        do {
            _ = try await client.health()

            let status = try await client.authStatus()
            if status.authEnabled ?? true {
                let login = try await client.login(password: password)
                if login.ok != true {
                    throw APIError.server(message: login.error ?? login.message ?? "Login failed. Check your password.")
                }
            }

            self.client = client
            serverURLString = trimmed
            UserDefaults.standard.set(trimmed, forKey: Self.serverURLKey)
            if !password.isEmpty {
                KeychainStore.savePassword(password, forServer: trimmed)
            }
            phase = .connected

            await refreshSessions()
            await loadModels()
        } catch {
            phase = .disconnected
            connectionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        if let client {
            Task { _ = try? await client.logout() }
        }
        client = nil
        phase = .disconnected
        sessions = []
        modelOptions = []
        selectedModel = nil
        selectedSessionID = nil
    }

    func refreshSessions() async {
        guard let client else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            let response = try await client.sessions()
            let visible = (response.sessions ?? []).filter { $0.archived != true }
            sessions = visible.sorted { lhs, rhs in
                if (lhs.pinned ?? false) != (rhs.pinned ?? false) {
                    return lhs.pinned ?? false
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            sessionsError = nil
        } catch {
            sessionsError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadModels() async {
        guard let client else { return }
        do {
            let response = try await client.models()
            modelOptions = response.options
            defaultModelID = response.defaultModel
            if selectedModel == nil, let defaultModelID {
                selectedModel = modelOptions.first { $0.id == defaultModelID }
            }
        } catch {
            // Model picker is optional; chat still works with the server default.
        }
    }

    func createSession() async {
        guard let client else { return }
        do {
            let response = try await client.createSession(
                workspace: nil,
                model: selectedModel?.id,
                modelProvider: selectedModel?.providerID
            )
            await refreshSessions()
            if let newID = response.session?.sessionId {
                selectedSessionID = newID
            }
        } catch {
            sessionsError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func renameSession(id: String, title: String) async {
        guard let client else { return }
        _ = try? await client.renameSession(id: id, title: title)
        await refreshSessions()
    }

    func deleteSession(id: String) async {
        guard let client else { return }
        _ = try? await client.deleteSession(id: id)
        if selectedSessionID == id {
            selectedSessionID = nil
        }
        await refreshSessions()
    }
}
