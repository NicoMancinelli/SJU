import Foundation

/// Server-sent-events reader for `/api/chat/stream`, built on
/// `URLSession.bytes(for:)` so it needs no third-party EventSource.
/// The server closes the socket after one of the terminal frames
/// (`stream_end`, `cancel`, `error`, `apperror`), so no reconnect logic.
enum SSEStream {
    /// `onEventID` is called with each SSE `id:` value (the server's sequence
    /// number), so callers can reconnect with `replay=1&after_seq=<last id>`.
    static func events(
        url: URL,
        onEventID: (@Sendable (String) -> Void)? = nil
    ) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 60 * 60
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("no-cache, no-transform", forHTTPHeaderField: "Cache-Control")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

                let configuration = URLSessionConfiguration.default
                configuration.httpCookieStorage = .shared
                configuration.httpShouldSetCookies = true
                configuration.timeoutIntervalForRequest = 60 * 60
                configuration.timeoutIntervalForResource = 60 * 60 * 12
                configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }

                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 401 {
                            continuation.finish(throwing: APIError.unauthorized)
                            return
                        }
                        guard (200..<300).contains(httpResponse.statusCode) else {
                            continuation.finish(throwing: APIError.http(statusCode: httpResponse.statusCode, body: nil))
                            return
                        }
                    }

                    var eventType = ""
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        if line.isEmpty {
                            if !eventType.isEmpty || !dataLines.isEmpty {
                                let event = decode(eventType: eventType, data: dataLines.joined(separator: "\n"))
                                if case .ignored = event {} else {
                                    continuation.yield(event)
                                }
                            }
                            eventType = ""
                            dataLines = []
                            continue
                        }
                        if line.hasPrefix(":") { continue }

                        if line.hasPrefix("event:") {
                            eventType = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            var value = String(line.dropFirst("data:".count))
                            if value.hasPrefix(" ") { value.removeFirst() }
                            dataLines.append(value)
                        } else if line.hasPrefix("id:") {
                            let value = String(line.dropFirst("id:".count)).trimmingCharacters(in: .whitespaces)
                            if !value.isEmpty {
                                onEventID?(value)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.network(underlying: error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Internal (not private) so the decoding contract is unit-testable.
    static func decode(eventType: String, data: String) -> ServerEvent {
        let payload = json(from: data)

        switch eventType {
        case "token":
            return .token(string(payload, "text") ?? "")
        case "reasoning":
            return .reasoning(string(payload, "text") ?? "")
        case "interim_assistant":
            return .interimAssistant(
                text: string(payload, "text") ?? "",
                alreadyStreamed: bool(payload, "already_streamed") ?? false
            )
        case "pending_steer_leftover":
            return .pendingSteerLeftover(string(payload, "text") ?? "")
        case "tool":
            return .toolStarted(
                name: string(payload, "name") ?? "tool",
                preview: string(payload, "preview")
            )
        case "tool_complete":
            return .toolCompleted(
                name: string(payload, "name") ?? "tool",
                preview: string(payload, "preview"),
                isError: bool(payload, "is_error") ?? false
            )
        case "title":
            guard let title = string(payload, "title"), !title.isEmpty else { return .ignored }
            return .title(title)
        case "done":
            return .done
        case "stream_end":
            return .streamEnd
        case "cancel":
            return .cancelled
        case "error", "apperror":
            let message = string(payload, "error") ?? string(payload, "message") ?? "The stream returned an error."
            return .error(message)
        default:
            return .ignored
        }
    }

    private static func json(from data: String) -> [String: Any]? {
        guard let bytes = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }

    private static func string(_ payload: [String: Any]?, _ key: String) -> String? {
        payload?[key] as? String
    }

    private static func bool(_ payload: [String: Any]?, _ key: String) -> Bool? {
        payload?[key] as? Bool
    }
}
