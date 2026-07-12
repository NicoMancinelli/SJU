import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case network(underlying: Error)
    case unauthorized
    case http(statusCode: Int, body: String?)
    case decoding(underlying: Error)
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is invalid."
        case .network(let underlying):
            return underlying.localizedDescription
        case .unauthorized:
            return "The server rejected the request (401). Check your password."
        case .http(let statusCode, let body):
            if let body, !body.isEmpty {
                return "Server error \(statusCode): \(body.prefix(200))"
            }
            return "Server error \(statusCode)."
        case .decoding:
            return "The server returned a response this app couldn't read."
        case .server(let message):
            return message
        }
    }
}

/// Minimal hermes-webui client. Auth is a session cookie set by
/// `POST /api/auth/login`, kept in the shared cookie storage so the SSE
/// stream requests carry it too.
final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Endpoints

    func health() async throws -> HealthResponse {
        try await get(path: "/health")
    }

    func authStatus() async throws -> AuthStatusResponse {
        try await get(path: "/api/auth/status")
    }

    func login(password: String) async throws -> LoginResponse {
        struct Body: Encodable { let password: String }
        return try await post(path: "/api/auth/login", body: Body(password: password))
    }

    func logout() async throws -> LoginResponse {
        struct Body: Encodable {}
        return try await post(path: "/api/auth/logout", body: Body())
    }

    func sessions() async throws -> SessionsResponse {
        try await get(path: "/api/sessions")
    }

    func session(id: String, messageLimit: Int = 200) async throws -> SessionResponse {
        try await get(path: "/api/session", query: [
            URLQueryItem(name: "session_id", value: id),
            URLQueryItem(name: "messages", value: "1"),
            URLQueryItem(name: "msg_limit", value: "\(messageLimit)")
        ])
    }

    func createSession(workspace: String?, model: String?, modelProvider: String?) async throws -> SessionResponse {
        struct Body: Encodable {
            let workspace: String?
            let model: String?
            let modelProvider: String?
        }
        return try await post(
            path: "/api/session/new",
            body: Body(workspace: workspace, model: model, modelProvider: modelProvider)
        )
    }

    func searchSessions(query: String) async throws -> SessionSearchResponse {
        try await get(path: "/api/sessions/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "content", value: "1"),
            URLQueryItem(name: "depth", value: "5")
        ])
    }

    func pinSession(id: String, pinned: Bool) async throws -> SessionMutationResponse {
        struct Body: Encodable {
            let sessionId: String
            let pinned: Bool
        }
        return try await post(path: "/api/session/pin", body: Body(sessionId: id, pinned: pinned))
    }

    func archiveSession(id: String, archived: Bool) async throws -> SessionMutationResponse {
        struct Body: Encodable {
            let sessionId: String
            let archived: Bool
        }
        return try await post(path: "/api/session/archive", body: Body(sessionId: id, archived: archived))
    }

    func workspaces() async throws -> WorkspacesResponse {
        try await get(path: "/api/workspaces")
    }

    func renameSession(id: String, title: String) async throws -> SessionMutationResponse {
        struct Body: Encodable {
            let sessionId: String
            let title: String
        }
        return try await post(path: "/api/session/rename", body: Body(sessionId: id, title: title))
    }

    func deleteSession(id: String) async throws -> SessionMutationResponse {
        struct Body: Encodable { let sessionId: String }
        return try await post(path: "/api/session/delete", body: Body(sessionId: id))
    }

    func models() async throws -> ModelsResponse {
        try await get(path: "/api/models")
    }

    func startChat(
        sessionID: String,
        message: String,
        model: String?,
        modelProvider: String?,
        attachments: [AttachmentPayload]? = nil
    ) async throws -> ChatStartResponse {
        struct Body: Encodable {
            let sessionId: String
            let message: String
            let model: String?
            let modelProvider: String?
            let explicitModelPick: Bool?
            let attachments: [AttachmentPayload]?
        }
        return try await post(
            path: "/api/chat/start",
            body: Body(
                sessionId: sessionID,
                message: message,
                model: model,
                modelProvider: modelProvider,
                explicitModelPick: model == nil ? nil : true,
                attachments: attachments
            )
        )
    }

    func uploadFile(sessionID: String, data: Data, filename: String) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url(path: "/api/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"session_id\"\r\n\r\n".utf8))
        body.append(Data("\(sessionID)\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        return try await run(request)
    }

    // MARK: Skills

    func skills() async throws -> SkillsResponse {
        try await get(path: "/api/skills")
    }

    func toggleSkill(name: String, enabled: Bool) async throws -> ToggleSkillResponse {
        struct Body: Encodable {
            let name: String
            let enabled: Bool
        }
        return try await post(path: "/api/skills/toggle", body: Body(name: name, enabled: enabled))
    }

    // MARK: Tasks (crons)

    func crons() async throws -> CronJobsResponse {
        try await get(path: "/api/crons")
    }

    func runCron(jobID: String) async throws -> CronMutationResponse {
        struct Body: Encodable { let jobId: String }
        return try await post(path: "/api/crons/run", body: Body(jobId: jobID))
    }

    func pauseCron(jobID: String) async throws -> CronMutationResponse {
        struct Body: Encodable { let jobId: String }
        return try await post(path: "/api/crons/pause", body: Body(jobId: jobID))
    }

    func resumeCron(jobID: String) async throws -> CronMutationResponse {
        struct Body: Encodable { let jobId: String }
        return try await post(path: "/api/crons/resume", body: Body(jobId: jobID))
    }

    // MARK: Memory

    func memory() async throws -> MemoryResponse {
        try await get(path: "/api/memory")
    }

    func cancelChat(streamID: String) async throws -> ChatCancelResponse {
        try await get(path: "/api/chat/cancel", query: [URLQueryItem(name: "stream_id", value: streamID)])
    }

    func steerChat(sessionID: String, text: String) async throws -> ChatSteerResponse {
        struct Body: Encodable {
            let sessionId: String
            let text: String
        }
        return try await post(path: "/api/chat/steer", body: Body(sessionId: sessionID, text: text))
    }

    func approvalPending(sessionID: String) async throws -> ApprovalPendingResponse {
        try await get(path: "/api/approval/pending", query: [URLQueryItem(name: "session_id", value: sessionID)])
    }

    func respondApproval(sessionID: String, choice: ApprovalChoice, approvalID: String?) async throws -> ApprovalRespondResponse {
        struct Body: Encodable {
            let sessionId: String
            let choice: ApprovalChoice
            let approvalId: String?
        }
        return try await post(
            path: "/api/approval/respond",
            body: Body(sessionId: sessionID, choice: choice, approvalId: approvalID)
        )
    }

    func clarifyPending(sessionID: String) async throws -> ClarificationPendingResponse {
        try await get(path: "/api/clarify/pending", query: [URLQueryItem(name: "session_id", value: sessionID)])
    }

    func respondClarification(sessionID: String, response: String, clarifyID: String?) async throws -> ClarificationRespondResponse {
        struct Body: Encodable {
            let sessionId: String
            let response: String
            let clarifyId: String?
        }
        return try await post(
            path: "/api/clarify/respond",
            body: Body(sessionId: sessionID, response: response, clarifyId: clarifyID)
        )
    }

    func chatStreamURL(streamID: String, replayAfterSeq: Int? = nil) -> URL {
        var query = [URLQueryItem(name: "stream_id", value: streamID)]
        if let replayAfterSeq {
            query.append(URLQueryItem(name: "replay", value: "1"))
            query.append(URLQueryItem(name: "after_seq", value: "\(max(0, replayAfterSeq))"))
        }
        return url(path: "/api/chat/stream", query: query)
    }

    // MARK: - Transport

    private func url(path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        components?.path = basePath.hasSuffix("/") ? basePath + String(path.dropFirst()) : basePath + path
        if !query.isEmpty {
            components?.queryItems = query
        }
        return components?.url ?? baseURL
    }

    private func get<Response: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> Response {
        var request = URLRequest(url: url(path: path, query: query))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await run(request)
    }

    private func post<Response: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await run(request)
    }

    private func run<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.http(statusCode: -1, body: nil)
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }
}
