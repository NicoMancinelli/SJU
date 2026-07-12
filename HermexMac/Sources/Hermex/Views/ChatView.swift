import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ChatViewModel

    init(sessionID: String, client: APIClient) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(sessionID: sessionID, client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
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
                if let lastID = viewModel.items.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message your agent…", text: $viewModel.composerText, axis: .vertical)
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
                    .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            Label(item.text, systemImage: "wrench.and.screwdriver")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .errorNote:
            Label(item.text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
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
                    Text(attributed(prose))
                        .textSelection(.enabled)
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

    private func attributed(_ string: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }
}
