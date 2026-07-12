import Foundation

// All fields optional: hermes-webui responses vary across versions, and the
// client must never fail to decode because a server added or dropped a key.

struct HealthResponse: Decodable {
    let status: String?
    let sessions: Int?
    let activeStreams: Int?
    let uptimeSeconds: Double?
}

struct AuthStatusResponse: Decodable {
    let authEnabled: Bool?
    let loggedIn: Bool?
    let passwordAuthEnabled: Bool?
}

struct LoginResponse: Decodable {
    let ok: Bool?
    let message: String?
    let error: String?
}

struct SessionsResponse: Decodable {
    let sessions: [SessionSummary]?
}

struct SessionSummary: Decodable, Identifiable, Hashable {
    var id: String { sessionId ?? "session-\(title ?? "untitled")-\(createdAt ?? 0)" }

    let sessionId: String?
    let title: String?
    let workspace: String?
    let model: String?
    let modelProvider: String?
    let messageCount: Int?
    let createdAt: Double?
    let updatedAt: Double?
    let lastMessageAt: Double?
    let pinned: Bool?
    let archived: Bool?
    let isStreaming: Bool?
    let activeStreamId: String?

    var displayTitle: String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled session" : trimmed
    }

    var sortTimestamp: Double { lastMessageAt ?? updatedAt ?? createdAt ?? 0 }
}

struct SessionSearchResponse: Decodable {
    let sessions: [SessionSummary]?
}

struct SessionResponse: Decodable {
    let session: SessionDetail?
}

struct SessionDetail: Decodable {
    let sessionId: String?
    let title: String?
    let workspace: String?
    let model: String?
    let modelProvider: String?
    let activeStreamId: String?
    let messages: [ChatMessage]?
}

struct SessionMutationResponse: Decodable {
    let ok: Bool?
    let error: String?
}

struct ChatMessage: Decodable, Identifiable, Equatable {
    var id: String { messageId ?? "\(role ?? "unknown")-\(timestamp ?? 0)-\(content?.hashValue ?? 0)" }

    let role: String?
    let content: String?
    let timestamp: Double?
    let messageId: String?
    let reasoning: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case timestamp
        case messageId
        case reasoning
        case underscoredTimestamp = "_ts"
    }

    init(role: String?, content: String?, timestamp: Double?, messageId: String?, reasoning: String? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.messageId = messageId
        self.reasoning = reasoning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
        // `content` may be a plain string or an array of typed parts; join the
        // text parts when it is an array so tool-heavy transcripts still render.
        if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
            content = text
        } else if let parts = try? container.decodeIfPresent([ContentPart].self, forKey: .content) {
            let joined = parts.compactMap(\.text).joined(separator: "\n")
            content = joined.isEmpty ? nil : joined
        } else {
            content = nil
        }
        timestamp = (try? container.decodeIfPresent(Double.self, forKey: .underscoredTimestamp))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .timestamp))
        messageId = try? container.decodeIfPresent(String.self, forKey: .messageId)
        reasoning = try? container.decodeIfPresent(String.self, forKey: .reasoning)
    }

    private struct ContentPart: Decodable {
        let type: String?
        let text: String?
    }
}

struct ChatStartResponse: Decodable {
    let streamId: String?
    let sessionId: String?
    let error: String?
}

struct ChatCancelResponse: Decodable {
    let ok: Bool?
    let cancelled: Bool?
    let error: String?
}

struct ChatSteerResponse: Decodable {
    let accepted: Bool?
    let fallback: String?
    let error: String?
}

// MARK: - Workspaces

struct WorkspacesResponse: Decodable {
    let workspaces: [WorkspaceRoot]?
    let last: String?
}

/// A workspace entry; servers send either a bare path string or an object.
struct WorkspaceRoot: Decodable, Identifiable, Hashable {
    var id: String { path ?? name ?? "workspace" }

    let path: String?
    let name: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        guard let path, !path.isEmpty else { return "Workspace" }
        return (path as NSString).lastPathComponent
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
    }

    init(from decoder: Decoder) throws {
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            path = stringValue
            name = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
    }
}

// MARK: - Approvals & clarifications

struct ApprovalPendingResponse: Decodable {
    let pending: PendingApproval?
    let pendingCount: Int?
}

struct PendingApproval: Decodable, Identifiable, Equatable {
    var id: String { approvalId ?? "\(command ?? "")-\(description ?? "")" }

    let approvalId: String?
    let command: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case approvalId
        case id
        case command
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primary = try? container.decodeIfPresent(String.self, forKey: .approvalId)
        let fallback = try? container.decodeIfPresent(String.self, forKey: .id)
        approvalId = [primary, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        command = try? container.decodeIfPresent(String.self, forKey: .command)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
    }
}

enum ApprovalChoice: String, Encodable, CaseIterable {
    case once
    case session
    case always
    case deny

    var label: String {
        switch self {
        case .once: return "Allow Once"
        case .session: return "Allow for Session"
        case .always: return "Always Allow"
        case .deny: return "Deny"
        }
    }
}

struct ApprovalRespondResponse: Decodable {
    let ok: Bool?
}

struct ClarificationPendingResponse: Decodable {
    let pending: PendingClarification?
    let pendingCount: Int?
}

struct PendingClarification: Decodable, Identifiable, Equatable {
    var id: String { clarifyId ?? question ?? "clarification" }

    let clarifyId: String?
    let question: String?
    let choicesOffered: [String]?
}

struct ClarificationRespondResponse: Decodable {
    let ok: Bool?
}

// MARK: - Model catalog

struct ModelsResponse: Decodable {
    let groups: [ModelGroup]?
    let defaultModel: String?

    var options: [ModelOption] {
        (groups ?? []).flatMap { group in
            (group.models ?? []).compactMap { model -> ModelOption? in
                guard let id = model.id, !id.isEmpty else { return nil }
                return ModelOption(
                    id: id,
                    displayName: model.name ?? model.label ?? id,
                    providerID: model.providerId ?? group.providerId,
                    groupName: group.name ?? group.providerId ?? "Models"
                )
            }
        }
    }
}

struct ModelGroup: Decodable {
    let name: String?
    let providerId: String?
    let models: [ModelEntry]?
}

struct ModelEntry: Decodable {
    let id: String?
    let name: String?
    let label: String?
    let providerId: String?
}

struct ModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let providerID: String?
    let groupName: String

    /// Stable across groups that repeat a model id under different providers.
    var pickerKey: String { "\(providerID ?? "-")/\(id)" }
}

// MARK: - Streaming events

enum ServerEvent {
    case token(String)
    case reasoning(String)
    case toolStarted(name: String, preview: String?)
    case toolCompleted(name: String, preview: String?, isError: Bool)
    case title(String)
    case done
    case streamEnd
    case cancelled
    case error(String)
    case ignored
}
