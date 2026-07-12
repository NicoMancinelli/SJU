import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @State private var renameTarget: SessionSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let sessionID = appState.selectedSessionID, let client = appState.client {
                ChatView(sessionID: sessionID, client: client)
                    .id(sessionID)
            } else {
                emptyDetail
            }
        }
        .navigationTitle("Hermex")
    }

    private var sidebar: some View {
        List(selection: $appState.selectedSessionID) {
            if let error = appState.sessionsError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            ForEach(appState.sessions) { session in
                SessionRow(session: session)
                    .tag(session.id)
                    .contextMenu {
                        Button("Rename…") {
                            renameTarget = session
                            renameText = session.displayTitle
                        }
                        Button("Delete", role: .destructive) {
                            Task { await appState.deleteSession(id: session.id) }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        .overlay {
            if appState.sessions.isEmpty && !appState.isLoadingSessions && appState.sessionsError == nil {
                VStack(spacing: 8) {
                    Text("No sessions yet")
                        .foregroundStyle(.secondary)
                    Button("New Session") {
                        Task { await appState.createSession() }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.createSession() }
                } label: {
                    Label("New Session", systemImage: "square.and.pencil")
                }
                .help("Start a new session")
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
