import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ChatViewModel
    @State private var showFileImporter = false
    @State private var isDropTargeted = false
    @State private var exportError: String?
    @State private var isExporting = false

    private let sessionID: String
    private let client: APIClient

    init(sessionID: String, client: APIClient) {
        self.sessionID = sessionID
        self.client = client
        _viewModel = StateObject(wrappedValue: ChatViewModel(sessionID: sessionID, client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let approval = viewModel.pendingApproval {
                ApprovalCard(approval: approval) { choice in
                    viewModel.respondToApproval(choice)
                }
            }
            if viewModel.pendingApproval == nil, let clarification = viewModel.pendingClarification {
                ClarificationCard(clarification: clarification) { answer in
                    viewModel.respondToClarification(answer)
                }
            }
            Divider()
            composer
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                viewModel.attachFiles(at: urls)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(SessionExportFormat.allCases) { format in
                        Button("Export as \(format.label)…") {
                            exportSession(format: format)
                        }
                    }
                } label: {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .help("Export this session")
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .task {
            viewModel.currentModelProvider = { [weak appState] in appState?.selectedModel }
            viewModel.onTitleChange = { [weak appState] _ in
                guard let appState else { return }
                Task { await appState.refreshSessions() }
            }
            await viewModel.loadHistory()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.canLoadEarlier && !viewModel.isLoading {
                        HStack {
                            Spacer()
                            Button {
                                Task { await viewModel.loadEarlier() }
                            } label: {
                                if viewModel.isLoadingEarlier {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Load earlier messages", systemImage: "arrow.up.circle")
                                }
                            }
                            .buttonStyle(.link)
                            Spacer()
                        }
                    }
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 40)
                    }
                    if let error = viewModel.loadError {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    ForEach(viewModel.items) { item in
                        MessageRow(item: item)
                            .id(item.id)
                    }
                    if viewModel.isStreaming {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .id("streaming-indicator")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: viewModel.items) { _ in
                if viewModel.suppressNextAutoscroll {
                    viewModel.suppressNextAutoscroll = false
                    return
                }
                if let lastID = viewModel.items.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    /// Downloads the server's export of this session and saves it where the
    /// user chooses.
    private func exportSession(format: SessionExportFormat) {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let export = try await client.exportSession(id: sessionID, format: format)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = export.filename
                panel.canCreateDirectories = true
                let response: NSApplication.ModalResponse
                if let window = NSApp.keyWindow {
                    response = await panel.beginSheetModal(for: window)
                } else {
                    response = panel.runModal()
                }
                guard response == .OK, let url = panel.url else { return }
                try export.data.write(to: url)
            } catch {
                exportError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            handled = true
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                guard let url else { return }
                Task { @MainActor in
                    viewModel.attachFiles(at: [url])
                }
            }
        }
        return handled
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.attachments.isEmpty || viewModel.isUploading {
                HStack(spacing: 6) {
                    ForEach(viewModel.attachments) { attachment in
                        HStack(spacing: 4) {
                            Image(systemName: attachment.isImage ? "photo" : "doc")
                                .font(.caption)
                            Text(attachment.name)
                                .font(.caption)
                                .lineLimit(1)
                            Button {
                                viewModel.removeAttachment(attachment)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                    }
                    if viewModel.isUploading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isStreaming)
                .help("Attach files")

                TextField(
                    viewModel.isStreaming ? "Steer the run…" : "Message your agent…",
                    text: $viewModel.composerText,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.separator)
                    )
                    .onSubmit {
                        viewModel.send()
                    }

                if viewModel.isStreaming {
                    Button {
                        viewModel.send()
                    } label: {
                        Image(systemName: "arrow.uturn.right.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Steer the run")

                    Button {
                        viewModel.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .help("Stop the run")
                } else {
                    Button {
                        viewModel.send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && viewModel.attachments.isEmpty
                    )
                    .help("Send (Return)")
                }
            }

            HStack {
                modelPicker
                Spacer()
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var modelPicker: some View {
        if appState.modelOptions.isEmpty {
            EmptyView()
        } else {
            Menu {
                Button("Server default") {
                    appState.selectedModel = nil
                }
                Divider()
                ForEach(groupedModelNames, id: \.self) { group in
                    Section(group) {
                        ForEach(appState.modelOptions.filter { $0.groupName == group }, id: \.pickerKey) { option in
                            Button {
                                appState.selectedModel = option
                            } label: {
                                if appState.selectedModel?.pickerKey == option.pickerKey {
                                    Label(option.displayName, systemImage: "checkmark")
                                } else {
                                    Text(option.displayName)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(appState.selectedModel?.displayName ?? "Server default", systemImage: "cpu")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var groupedModelNames: [String] {
        var seen = Set<String>()
        return appState.modelOptions.compactMap { option in
            seen.insert(option.groupName).inserted ? option.groupName : nil
        }
    }
}

private struct MessageRow: View {
    let item: ChatViewModel.TranscriptItem
    @State private var showReasoning = false

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentColor.opacity(0.18))
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if !item.reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $showReasoning) {
                        Text(item.reasoning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Label("Reasoning", systemImage: "brain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                MarkdownText(text: item.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .toolNote:
            VStack(alignment: .leading, spacing: 3) {
                Label(item.text, systemImage: "wrench.and.screwdriver")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(.leading, 24)
                }
            }
        case .errorNote:
            Label(item.text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

private struct ApprovalCard: View {
    let approval: PendingApproval
    let respond: (ApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The agent wants to run a command", systemImage: "lock.shield")
                .font(.headline)
            if let command = approval.command, !command.isEmpty {
                ScrollView(.horizontal) {
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
            if let description = approval.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(ApprovalChoice.allCases, id: \.rawValue) { choice in
                    Button(choice.label) {
                        respond(choice)
                    }
                    .tint(choice == .deny ? .red : nil)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }
}

private struct ClarificationCard: View {
    let clarification: PendingClarification
    let respond: (String) -> Void
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The agent has a question", systemImage: "questionmark.bubble")
                .font(.headline)
            if let question = clarification.question, !question.isEmpty {
                Text(question)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            if let choices = clarification.choicesOffered, !choices.isEmpty {
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) {
                            respond(choice)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Answer…", text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { respond(answer) }
                Button("Reply") { respond(answer) }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }
}

/// Lightweight rendering: paragraph-level inline Markdown via AttributedString,
/// with fenced code blocks pulled out into monospaced boxes.
private struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let prose):
                    ProseBlocks(text: prose)
                case .code(let code):
                    ScrollView(.horizontal) {
                        Text(code)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.separator)
                    )
                }
            }
        }
    }

    private enum Segment {
        case prose(String)
        case code(String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var prose: [String] = []
        var code: [String] = []
        var inCode = false

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(code.joined(separator: "\n")))
                    code = []
                } else {
                    let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !joined.isEmpty { result.append(.prose(joined)) }
                    prose = []
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode, !code.isEmpty {
            result.append(.code(code.joined(separator: "\n")))
        }
        let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { result.append(.prose(joined)) }
        return result
    }

}

/// Block-level rendering for a prose segment: headings, bullet/numbered list
/// rows, block quotes, and paragraphs — inline Markdown within each.
private struct ProseBlocks: View {
    let text: String

    private enum Block {
        case heading(level: Int, text: String)
        case listRow(marker: String, text: String)
        case quote(String)
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let heading):
                    Text(inline(heading))
                        .font(level <= 1 ? .title2.weight(.semibold)
                              : level == 2 ? .title3.weight(.semibold)
                              : .headline)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                case .listRow(let marker, let rowText):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker)
                            .foregroundStyle(.secondary)
                        Text(inline(rowText))
                            .textSelection(.enabled)
                    }
                    .padding(.leading, 4)
                case .quote(let quote):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.tertiary)
                            .frame(width: 3)
                        Text(inline(quote))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                case .paragraph(let paragraph):
                    Text(inline(paragraph))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var quote: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { result.append(.paragraph(joined)) }
            paragraph = []
        }
        func flushQuote() {
            let joined = quote.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { result.append(.quote(joined)) }
            quote = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushQuote()
                continue
            }

            if line.hasPrefix("#") {
                flushParagraph()
                flushQuote()
                let level = line.prefix(while: { $0 == "#" }).count
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if level <= 6 && !heading.isEmpty {
                    result.append(.heading(level: level, text: heading))
                    continue
                }
            }

            if line.hasPrefix("> ") || line == ">" {
                flushParagraph()
                quote.append(String(line.dropFirst(line == ">" ? 1 : 2)))
                continue
            }

            if let bullet = bulletContent(of: line) {
                flushParagraph()
                flushQuote()
                result.append(.listRow(marker: "•", text: bullet))
                continue
            }

            if let (number, content) = numberedContent(of: line) {
                flushParagraph()
                flushQuote()
                result.append(.listRow(marker: "\(number).", text: content))
                continue
            }

            flushQuote()
            paragraph.append(rawLine)
        }
        flushParagraph()
        flushQuote()
        return result
    }

    private func bulletContent(of line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private func numberedContent(of line: String) -> (Int, String)? {
        guard let dotIndex = line.firstIndex(of: "."), dotIndex != line.startIndex else { return nil }
        let numberPart = line[line.startIndex..<dotIndex]
        guard numberPart.count <= 3, let number = Int(numberPart) else { return nil }
        let rest = line[line.index(after: dotIndex)...]
        guard rest.hasPrefix(" ") else { return nil }
        return (number, rest.trimmingCharacters(in: .whitespaces))
    }

    private func inline(_ string: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }
}
