import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @State private var renameTarget: SessionSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                tabPicker
                Divider()
                if appState.sidebarTab == .chats {
                    sidebar
                } else {
                    panelSidebarPlaceholder
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .navigationTitle("Hermex")
    }

    private var tabPicker: some View {
        Picker("Section", selection: $appState.sidebarTab) {
            ForEach(SidebarTab.allCases) { tab in
                Image(systemName: tab.systemImage)
                    .help(tab.label)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(10)
    }

    /// The non-chat panels render in the detail column; their sidebar side
    /// just names the section.
    private var panelSidebarPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: appState.sidebarTab.systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.sidebarTab.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        if let client = appState.client {
            switch appState.sidebarTab {
            case .chats:
                if let sessionID = appState.selectedSessionID {
                    ChatView(sessionID: sessionID, client: client)
                        .id(sessionID)
                } else {
                    emptyDetail
                }
            case .skills:
                SkillsView(client: client)
            case .tasks:
                TasksView(client: client)
            case .memory:
                MemoryView(client: client)
            }
        } else {
            emptyDetail
        }
    }

    private var sidebar: some View {
        List(selection: $appState.selectedSessionID) {
            if let error = appState.sessionsError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            ForEach(appState.displayedSessions) { session in
                SessionRow(session: session)
                    .tag(session.id)
                    .contextMenu {
                        Button(session.pinned == true ? "Unpin" : "Pin") {
                            Task { await appState.pinSession(id: session.id, pinned: session.pinned != true) }
                        }
                        Button("Rename…") {
                            renameTarget = session
                            renameText = session.displayTitle
                        }
                        Divider()
                        Button("Archive") {
                            Task { await appState.archiveSession(id: session.id) }
                        }
                        Button("Delete", role: .destructive) {
                            Task { await appState.deleteSession(id: session.id) }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $appState.searchQuery, placement: .sidebar, prompt: "Search sessions")
        .onChange(of: appState.searchQuery) { _ in
            appState.searchQueryChanged()
        }
        .overlay {
            if appState.displayedSessions.isEmpty && !appState.isLoadingSessions && appState.sessionsError == nil {
                if appState.searchResults != nil {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                        Button("New Session") {
                            Task { await appState.createSession() }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                newSessionControl
            }
            ToolbarItem {
                Button {
                    Task { await appState.refreshSessions() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh sessions")
            }
        }
        .refreshable {
            await appState.refreshSessions()
        }
        .sheet(item: $renameTarget) { session in
            RenameSheet(title: $renameText) {
                let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renameTarget = nil
                guard !newTitle.isEmpty else { return }
                Task { await appState.renameSession(id: session.id, title: newTitle) }
            } onCancel: {
                renameTarget = nil
            }
        }
    }

    /// Plain button when the server has no registered workspaces; a menu of
    /// workspace choices when it does.
    @ViewBuilder
    private var newSessionControl: some View {
        if appState.workspaces.isEmpty {
            Button {
                Task { await appState.createSession() }
            } label: {
                Label("New Session", systemImage: "square.and.pencil")
            }
            .help("Start a new session")
        } else {
            Menu {
                Button("Default Workspace") {
                    Task { await appState.createSession() }
                }
                Divider()
                ForEach(appState.workspaces) { workspace in
                    Button(workspace.displayName) {
                        Task { await appState.createSession(workspace: workspace.path) }
                    }
                }
            } label: {
                Label("New Session", systemImage: "square.and.pencil")
            }
            .help("Start a new session in a workspace")
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select a session, or start a new one.")
                .foregroundStyle(.secondary)
            Button("New Session") {
                Task { await appState.createSession() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if session.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(session.displayTitle)
                    .lineLimit(1)
                if session.isStreaming == true {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            HStack(spacing: 6) {
                if let workspace = session.workspace, !workspace.isEmpty {
                    Text((workspace as NSString).lastPathComponent)
                        .lineLimit(1)
                }
                if let model = session.model, !model.isEmpty {
                    Text(model)
                        .lineLimit(1)
                }
                if session.sortTimestamp > 0 {
                    Text(Date(timeIntervalSince1970: session.sortTimestamp), style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct RenameSheet: View {
    @Binding var title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Session")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(onSave)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
