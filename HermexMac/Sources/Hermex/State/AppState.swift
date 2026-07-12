import Foundation
import SwiftUI

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case connected
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case chats
    case skills
    case tasks
    case memory
    case insights
    case files

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chats: return "Chats"
        case .skills: return "Skills"
        case .tasks: return "Tasks"
        case .memory: return "Memory"
        case .insights: return "Insights"
        case .files: return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .skills: return "sparkles"
        case .tasks: return "calendar.badge.clock"
        case .memory: return "brain"
        case .insights: return "chart.bar"
        case .files: return "folder"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: ConnectionPhase = .disconnected
    @Published var serverURLString: String
    @Published var connectionError: String?

    @Published var sessions: [SessionSummary] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false

    @Published var searchQuery = ""
    @Published var searchResults: [SessionSummary]?

    @Published var workspaces: [WorkspaceRoot] = []
    @Published var lastWorkspace: String?

    @Published var profiles: [ProfileSummary] = []
    @Published var activeProfile: String?
    @Published var actionNotice: String?
    /// Bumped when a server-side action rewrites an open transcript
    /// (undo, compress), forcing the chat view to reload history.
    @Published var transcriptReloadToken = 0

    private var searchTask: Task<Void, Never>?

    @Published var modelOptions: [ModelOption] = []
    @Published var defaultModelID: String?
    @Published var selectedModel: ModelOption?

    @Published var selectedSessionID: String?
    @Published var sidebarTab: SidebarTab = .chats

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

            // A still-valid session cookie means no login round-trip is needed.
            let status = try await client.authStatus()
            if (status.authEnabled ?? true) && status.loggedIn != true {
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
            await loadWorkspaces()
            await loadProfiles()
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
        workspaces = []
        lastWorkspace = nil
        searchQuery = ""
        searchResults = nil
        profiles = []
        activeProfile = nil
    }

    /// Rows the sidebar shows: search results while a query is active,
    /// otherwise the full visible session list.
    var displayedSessions: [SessionSummary] {
        searchResults ?? sessions
    }

    func searchQueryChanged() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }

        searchTask = Task { [weak self] in
            // Debounce keystrokes before hitting the server.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self, let client = self.client else { return }
            do {
                let response = try await client.searchSessions(query: query)
                if !Task.isCancelled && self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query {
                    self.searchResults = response.sessions ?? []
                }
            } catch {
                // Fall back to a local title filter when the server can't search.
                if !Task.isCancelled {
                    self.searchResults = self.sessions.filter {
                        $0.displayTitle.localizedCaseInsensitiveContains(query)
                    }
                }
            }
        }
    }

    func loadWorkspaces() async {
        guard let client else { return }
        do {
            let response = try await client.workspaces()
            workspaces = (response.workspaces ?? []).filter { !($0.path ?? "").isEmpty }
            lastWorkspace = response.last
        } catch {
            // Workspace picker is optional; new sessions use the server default.
        }
    }

    func loadProfiles() async {
        guard let client else { return }
        do {
            let response = try await client.profiles()
            profiles = response.profiles ?? []
            activeProfile = response.active
        } catch {
            // Profile switching is optional; single-profile servers work without it.
        }
    }

    /// Switching the profile changes what the whole server surface shows, so
    /// every cached catalog reloads afterwards.
    func switchProfile(name: String) async {
        guard let client else { return }
        do {
            let response = try await client.switchProfile(name: name)
            if let error = response.error {
                actionNotice = error
                return
            }
            activeProfile = response.active ?? name
            selectedSessionID = nil
            selectedModel = nil
            await refreshSessions()
            await loadModels()
            await loadWorkspaces()
            await loadProfiles()
        } catch {
            actionNotice = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func branchSession(id: String) async {
        guard let client else { return }
        do {
            let response = try await client.branchSession(id: id)
            if let error = response.error {
                actionNotice = error
                return
            }
            await refreshSessions()
            if let newID = response.sessionId {
                selectedSessionID = newID
            }
        } catch {
            actionNotice = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func compressSession(id: String) async {
        guard let client else { return }
        do {
            let response = try await client.compressSession(id: id)
            if response.ok != true, let error = response.error {
                actionNotice = error
            } else {
                actionNotice = "Session compressed."
                if selectedSessionID == id {
                    transcriptReloadToken += 1
                }
            }
            await refreshSessions()
        } catch {
            actionNotice = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func undoSession(id: String) async {
        guard let client else { return }
        do {
            let response = try await client.undoSession(id: id)
            if response.ok != true, let error = response.error {
                actionNotice = error
            } else {
                if let removed = response.removedCount {
                    actionNotice = "Removed \(removed) message\(removed == 1 ? "" : "s")."
                }
                if selectedSessionID == id {
                    transcriptReloadToken += 1
                }
            }
            await refreshSessions()
        } catch {
            actionNotice = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func pinSession(id: String, pinned: Bool) async {
        guard let client else { return }
        _ = try? await client.pinSession(id: id, pinned: pinned)
        await refreshSessions()
    }

    func archiveSession(id: String) async {
        guard let client else { return }
        _ = try? await client.archiveSession(id: id, archived: true)
        if selectedSessionID == id {
            selectedSessionID = nil
        }
        await refreshSessions()
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

    func createSession(workspace: String? = nil) async {
        guard let client else { return }
        do {
            let response = try await client.createSession(
                workspace: workspace,
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
