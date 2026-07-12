import Foundation
import SwiftUI

/// One chat transcript: loads history for a session and drives a streaming run.
@MainActor
final class ChatViewModel: ObservableObject {
    struct TranscriptItem: Identifiable, Equatable {
        enum Kind: Equatable {
            case user
            case assistant
            case toolNote
            case errorNote
        }

        let id: String
        let kind: Kind
        var text: String
        var reasoning: String = ""
    }

    @Published var items: [TranscriptItem] = []
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var loadError: String?
    @Published var composerText = ""

    let sessionID: String
    private let client: APIClient
    private var streamTask: Task<Void, Never>?
    private var activeStreamID: String?
    private var nextLocalID = 0
    /// Called when the server pushes a generated session title mid-stream.
    var onTitleChange: ((String) -> Void)?

    init(sessionID: String, client: APIClient) {
        self.sessionID = sessionID
        self.client = client
    }

    func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.session(id: sessionID)
            let messages = response.session?.messages ?? []
            items = messages.compactMap { message in
                let role = message.role ?? ""
                let text = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                switch role {
                case "user":
                    return TranscriptItem(id: message.id, kind: .user, text: text)
                case "assistant":
                    return TranscriptItem(
                        id: message.id,
                        kind: .assistant,
                        text: text,
                        reasoning: message.reasoning ?? ""
                    )
                default:
                    // tool/system rows are noise in a compact transcript
                    return nil
                }
            }
            loadError = nil

            // If the server reports an in-flight run for this session, re-attach.
            if let streamID = response.session?.activeStreamId, !streamID.isEmpty {
                attachToStream(streamID: streamID)
            }
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func send() {
        let message = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isStreaming else { return }
        composerText = ""

        items.append(TranscriptItem(id: localID("user"), kind: .user, text: message))

        let model = currentModelProvider?()
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await self.client.startChat(
                    sessionID: self.sessionID,
                    message: message,
                    model: model?.id,
                    modelProvider: model?.providerID
                )
                if let error = start.error {
                    self.finishStream(errorText: error)
                    return
                }
                guard let streamID = start.streamId else {
                    self.finishStream(errorText: "The server did not return a stream id.")
                    return
                }
                await self.consumeStream(streamID: streamID)
            } catch {
                self.finishStream(errorText: (error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// The composer's model selection lives in AppState; injected as a closure
    /// so this view model doesn't own catalog state.
    var currentModelProvider: (() -> ModelOption?)?

    func stop() {
        guard let activeStreamID else {
            streamTask?.cancel()
            isStreaming = false
            return
        }
        Task {
            _ = try? await client.cancelChat(streamID: activeStreamID)
        }
    }

    private func attachToStream(streamID: String) {
        guard !isStreaming else { return }
        isStreaming = true
        streamTask = Task { [weak self] in
            await self?.consumeStream(streamID: streamID)
        }
    }

    private func consumeStream(streamID: String) async {
        activeStreamID = streamID
        let assistantID = localID("assistant")
        var assistantIndex: Int?

        func ensureAssistantRow() -> Int {
            if let assistantIndex { return assistantIndex }
            items.append(TranscriptItem(id: assistantID, kind: .assistant, text: ""))
            let index = items.count - 1
            assistantIndex = index
            return index
        }

        do {
            for try await event in SSEStream.events(url: client.chatStreamURL(streamID: streamID)) {
                switch event {
                case .token(let text):
                    let index = ensureAssistantRow()
                    items[index].text += text
                case .reasoning(let text):
                    let index = ensureAssistantRow()
                    items[index].reasoning += text
                case .toolStarted(let name):
                    items.append(TranscriptItem(id: localID("tool"), kind: .toolNote, text: "Running \(name)…"))
                case .toolCompleted(let name, let isError):
                    if let last = items.lastIndex(where: { $0.kind == .toolNote && $0.text == "Running \(name)…" }) {
                        items[last].text = isError ? "\(name) failed" : "Ran \(name)"
                    }
                    // A follow-up answer streams into a fresh bubble after tools.
                    assistantIndex = nil
                case .title(let title):
                    onTitleChange?(title)
                case .error(let message):
                    finishStream(errorText: message)
                    return
                case .cancelled, .streamEnd, .done:
                    continue
                case .ignored:
                    continue
                }
            }
            finishStream(errorText: nil)
        } catch {
            finishStream(errorText: (error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func finishStream(errorText: String?) {
        if let errorText, !errorText.isEmpty {
            items.append(TranscriptItem(id: localID("error"), kind: .errorNote, text: errorText))
        }
        // Drop any empty assistant placeholder left by a run with no tokens.
        items.removeAll { $0.kind == .assistant && $0.text.isEmpty && $0.reasoning.isEmpty }
        isStreaming = false
        activeStreamID = nil
        streamTask = nil
    }

    private func localID(_ prefix: String) -> String {
        nextLocalID += 1
        return "local-\(prefix)-\(nextLocalID)-\(Date().timeIntervalSince1970)"
    }
}
