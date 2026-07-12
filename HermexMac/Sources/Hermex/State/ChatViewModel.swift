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
        var detail: String = ""
        var toolName: String = ""
    }

    @Published var items: [TranscriptItem] = []
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var loadError: String?
    @Published var composerText = ""
    @Published var pendingApproval: PendingApproval?
    @Published var pendingClarification: PendingClarification?
    @Published var attachments: [PendingAttachment] = []
    @Published var isUploading = false
    @Published var canLoadEarlier = false
    @Published var isLoadingEarlier = false
    /// Set when items change by prepending history, so the view skips its
    /// scroll-to-bottom for that change.
    var suppressNextAutoscroll = false

    private var earliestOffset: Int?

    let sessionID: String
    private let client: APIClient
    private var streamTask: Task<Void, Never>?
    private var pendingPollTask: Task<Void, Never>?
    private var activeStreamID: String?
    private var lastEventSeq: Int?
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
            items = Self.transcriptItems(from: response.session?.messages ?? [])
            updatePaging(from: response.session)
            loadError = nil

            // If the server reports an in-flight run for this session, re-attach.
            if let streamID = response.session?.activeStreamId, !streamID.isEmpty {
                attachToStream(streamID: streamID)
            }
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Prepends the previous page of history (the server window ending just
    /// before the earliest message currently shown).
    func loadEarlier() async {
        guard canLoadEarlier, !isLoadingEarlier, let before = earliestOffset, before > 0 else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let response = try await client.session(id: sessionID, messageBefore: before)
            let earlier = Self.transcriptItems(from: response.session?.messages ?? [])
            let existingIDs = Set(items.map(\.id))
            suppressNextAutoscroll = true
            items.insert(contentsOf: earlier.filter { !existingIDs.contains($0.id) }, at: 0)
            updatePaging(from: response.session)
        } catch {
            // Leave the button; the user can retry.
        }
    }

    private func updatePaging(from session: SessionDetail?) {
        let offset = session?.messagesOffset ?? 0
        earliestOffset = offset
        canLoadEarlier = (session?.messagesTruncated == true) && offset > 0
    }

    private static func transcriptItems(from messages: [ChatMessage]) -> [TranscriptItem] {
        messages.compactMap { message in
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
    }

    func send() {
        let draft = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty || !attachments.isEmpty else { return }

        if isStreaming {
            guard !draft.isEmpty else { return }
            steer(draft)
            return
        }
        composerText = ""

        // Mirror the iOS client: attachment paths ride in a text marker in
        // addition to the structured `attachments` array.
        var message = draft
        let references = attachments.map(\.path).filter { !$0.isEmpty }
        if !references.isEmpty {
            message = "\(draft)\n\n[Attached files: \(references.joined(separator: ", "))]"
        }
        let payloads = attachments.isEmpty ? nil : attachments.map(AttachmentPayload.init)
        attachments = []

        items.append(TranscriptItem(
            id: localID("user"),
            kind: .user,
            text: draft.isEmpty ? "(attachments)" : draft
        ))

        let model = currentModelProvider?()
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await self.client.startChat(
                    sessionID: self.sessionID,
                    message: message,
                    model: model?.id,
                    modelProvider: model?.providerID,
                    attachments: payloads
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

    /// Sends steering text into the in-flight run. If the server can't accept
    /// a steer, it reports a fallback and the text is surfaced as a note.
    private func steer(_ text: String) {
        composerText = ""
        items.append(TranscriptItem(id: localID("user"), kind: .user, text: text))
        Task {
            do {
                let response = try await client.steerChat(sessionID: sessionID, text: text)
                if response.accepted != true {
                    let detail = response.error ?? response.fallback
                    items.append(TranscriptItem(
                        id: localID("steer"),
                        kind: .toolNote,
                        text: detail.map { "Steer not accepted: \($0)" } ?? "Steer queued for after the current run."
                    ))
                }
            } catch {
                items.append(TranscriptItem(
                    id: localID("error"),
                    kind: .errorNote,
                    text: (error as? APIError)?.errorDescription ?? error.localizedDescription
                ))
            }
        }
    }

    /// Uploads local files to the server and queues them for the next message.
    func attachFiles(at urls: [URL]) {
        guard !urls.isEmpty else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            for url in urls {
                let filename = url.lastPathComponent
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url) else {
                    items.append(TranscriptItem(
                        id: localID("error"),
                        kind: .errorNote,
                        text: "Couldn't read \(filename)."
                    ))
                    continue
                }
                guard data.count <= PendingAttachment.maximumUploadBytes else {
                    items.append(TranscriptItem(
                        id: localID("error"),
                        kind: .errorNote,
                        text: "\(filename) is too large. Attachments must be 20 MB or smaller."
                    ))
                    continue
                }
                do {
                    let response = try await client.uploadFile(sessionID: sessionID, data: data, filename: filename)
                    if let error = response.error {
                        throw APIError.server(message: error)
                    }
                    attachments.append(PendingAttachment(
                        name: response.filename ?? filename,
                        path: response.path ?? "",
                        mime: response.mime ?? "application/octet-stream",
                        size: response.size ?? data.count,
                        isImage: response.isImage ?? false
                    ))
                } catch {
                    items.append(TranscriptItem(
                        id: localID("error"),
                        kind: .errorNote,
                        text: "Upload of \(filename) failed: \((error as? APIError)?.errorDescription ?? error.localizedDescription)"
                    ))
                }
            }
        }
    }

    func removeAttachment(_ attachment: PendingAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func respondToApproval(_ choice: ApprovalChoice) {
        guard let approval = pendingApproval else { return }
        pendingApproval = nil
        Task {
            _ = try? await client.respondApproval(
                sessionID: sessionID,
                choice: choice,
                approvalID: approval.approvalId
            )
        }
    }

    func respondToClarification(_ answer: String) {
        guard let clarification = pendingClarification else { return }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingClarification = nil
        Task {
            _ = try? await client.respondClarification(
                sessionID: sessionID,
                response: trimmed,
                clarifyID: clarification.clarifyId
            )
        }
    }

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
        lastEventSeq = nil
        startPendingPolling()
        defer { stopPendingPolling() }

        var assistantIndex: Int?

        func ensureAssistantRow() -> Int {
            if let assistantIndex { return assistantIndex }
            items.append(TranscriptItem(id: localID("assistant"), kind: .assistant, text: ""))
            let index = items.count - 1
            assistantIndex = index
            return index
        }

        // One transport-level retry with replay: if the socket drops mid-run
        // (sleep, network blip), reconnect asking for events after the last
        // sequence number we saw.
        var attempt = 0
        while true {
            let replayAfter = attempt == 0 ? nil : (lastEventSeq ?? 0)
            let url = client.chatStreamURL(streamID: streamID, replayAfterSeq: replayAfter)
            do {
                for try await event in SSEStream.events(url: url, onEventID: { [weak self] id in
                    guard let seq = Int(id) else { return }
                    Task { @MainActor [weak self] in
                        self?.lastEventSeq = seq
                    }
                }) {
                    switch event {
                    case .token(let text):
                        let index = ensureAssistantRow()
                        items[index].text += text
                    case .reasoning(let text):
                        let index = ensureAssistantRow()
                        items[index].reasoning += text
                    case .toolStarted(let name, let preview):
                        var item = TranscriptItem(id: localID("tool"), kind: .toolNote, text: "Running \(name)…")
                        item.detail = preview ?? ""
                        item.toolName = name
                        items.append(item)
                    case .toolCompleted(let name, let preview, let isError):
                        if let last = items.lastIndex(where: { $0.kind == .toolNote && $0.toolName == name && $0.text.hasSuffix("…") }) {
                            items[last].text = isError ? "\(name) failed" : "Ran \(name)"
                            if let preview, !preview.isEmpty {
                                items[last].detail = preview
                            }
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
                return
            } catch {
                attempt += 1
                if attempt > 1 {
                    finishStream(errorText: (error as? APIError)?.errorDescription ?? error.localizedDescription)
                    return
                }
                // Brief pause, then check the run is still worth re-attaching to.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled {
                    finishStream(errorText: nil)
                    return
                }
            }
        }
    }

    /// While a run is active, poll for pending approval/clarification prompts
    /// so tool-permission requests surface without a dedicated event stream.
    private func startPendingPolling() {
        stopPendingPolling()
        pendingPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if let approval = try? await self.client.approvalPending(sessionID: self.sessionID) {
                    self.pendingApproval = approval.pending
                }
                if self.pendingApproval == nil,
                   let clarify = try? await self.client.clarifyPending(sessionID: self.sessionID) {
                    self.pendingClarification = clarify.pending
                }
            }
        }
    }

    private func stopPendingPolling() {
        pendingPollTask?.cancel()
        pendingPollTask = nil
        pendingApproval = nil
        pendingClarification = nil
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
