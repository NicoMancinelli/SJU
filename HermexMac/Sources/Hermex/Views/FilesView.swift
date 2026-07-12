import SwiftUI

/// Browser for the workspace of the currently selected session
/// (`/api/list` + `/api/file` are scoped by session on the server).
struct FilesView: View {
    let client: APIClient
    let sessionID: String?

    @State private var entries: [WorkspaceEntry] = []
    @State private var currentPath: String?
    @State private var workspaceLabel: String?
    @State private var pathStack: [String?] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var previewedFile: FileResponse?

    var body: some View {
        Group {
            if let sessionID {
                browser(sessionID: sessionID)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Select a session in Chats first — the file browser shows that session's workspace.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Files")
    }

    private func browser(sessionID: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    goUp(sessionID: sessionID)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(pathStack.isEmpty)
                .help("Back")
                Text(displayPath)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button {
                    Task { await load(sessionID: sessionID, path: currentPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(10)
            Divider()

            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Button("Retry") {
                        Task { await load(sessionID: sessionID, path: currentPath) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                entryList(sessionID: sessionID)
            }
        }
        .task(id: sessionID) {
            pathStack = []
            await load(sessionID: sessionID, path: nil)
        }
        .sheet(item: Binding(
            get: { previewedFile.map(FilePreviewItem.init) },
            set: { if $0 == nil { previewedFile = nil } }
        )) { item in
            FilePreviewSheet(file: item.file) {
                previewedFile = nil
            }
        }
    }

    private var displayPath: String {
        if let currentPath, !currentPath.isEmpty { return currentPath }
        if let workspaceLabel, !workspaceLabel.isEmpty { return workspaceLabel }
        return "Workspace root"
    }

    private func entryList(sessionID: String) -> some View {
        List(sortedEntries) { entry in
            Button {
                open(entry, sessionID: sessionID)
            } label: {
                HStack {
                    Image(systemName: entry.isBrowsableDirectory ? "folder.fill" : "doc.text")
                        .foregroundStyle(entry.isBrowsableDirectory ? Color.accentColor : Color.secondary)
                    Text(entry.name ?? (entry.path as NSString?)?.lastPathComponent ?? "—")
                        .lineLimit(1)
                    Spacer()
                    if !entry.isBrowsableDirectory, let size = entry.size {
                        Text(byteString(size))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if sortedEntries.isEmpty && !isLoading {
                Text("Empty directory")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sortedEntries: [WorkspaceEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isBrowsableDirectory != rhs.isBrowsableDirectory {
                return lhs.isBrowsableDirectory
            }
            return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedAscending
        }
    }

    private func open(_ entry: WorkspaceEntry, sessionID: String) {
        guard let path = entry.path, !path.isEmpty else { return }
        if entry.isBrowsableDirectory {
            pathStack.append(currentPath)
            Task { await load(sessionID: sessionID, path: path) }
        } else {
            Task {
                do {
                    let file = try await client.fileContent(sessionID: sessionID, path: path)
                    if let error = file.error {
                        loadError = error
                    } else {
                        previewedFile = file
                    }
                } catch {
                    loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func goUp(sessionID: String) {
        guard let previous = pathStack.popLast() else { return }
        Task { await load(sessionID: sessionID, path: previous) }
    }

    private func load(sessionID: String, path: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.directoryList(sessionID: sessionID, path: path)
            if let error = response.error {
                loadError = error
                return
            }
            entries = response.entries ?? []
            currentPath = response.path ?? path
            workspaceLabel = response.workspace
            loadError = nil
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct FilePreviewItem: Identifiable {
    let file: FileResponse
    var id: String { file.path ?? file.name ?? "file" }
}

private struct FilePreviewSheet: View {
    let file: FileResponse
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(file.name ?? (file.path as NSString?)?.lastPathComponent ?? "File")
                    .font(.headline)
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(file.content ?? "(empty file)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
