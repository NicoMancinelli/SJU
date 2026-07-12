import XCTest
@testable import Hermex

final class ModelDecodingTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: Models catalog

    func testModelsResponseOptionsFlattenGroups() throws {
        let json = """
        {
          "groups": [
            {"name": "Anthropic", "provider_id": "anthropic", "models": [
              {"id": "claude-1", "name": "Claude One"},
              {"id": "claude-2", "label": "Claude Two"}
            ]},
            {"name": "Local", "models": [
              {"id": "llama", "provider_id": "ollama"}
            ]}
          ],
          "default_model": "claude-1"
        }
        """
        let response = try decoder().decode(ModelsResponse.self, from: Data(json.utf8))
        let options = response.options
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[0].displayName, "Claude One")
        XCTAssertEqual(options[0].providerID, "anthropic")
        XCTAssertEqual(options[1].displayName, "Claude Two")
        XCTAssertEqual(options[2].providerID, "ollama")
        XCTAssertEqual(response.defaultModel, "claude-1")
    }

    func testModelsResponseSkipsEntriesWithoutID() throws {
        let json = #"{"groups": [{"name": "X", "models": [{"name": "no id"}, {"id": "ok"}]}]}"#
        let response = try decoder().decode(ModelsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.options.map(\.id), ["ok"])
    }

    // MARK: Chat messages

    func testChatMessageDecodesStringContent() throws {
        let json = #"{"role": "assistant", "content": "hi", "_ts": 12.5}"#
        let message = try decoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.content, "hi")
        XCTAssertEqual(message.timestamp, 12.5)
    }

    func testChatMessageDecodesContentPartsArray() throws {
        let json = """
        {"role": "assistant", "content": [
          {"type": "text", "text": "part one"},
          {"type": "tool_use"},
          {"type": "text", "text": "part two"}
        ]}
        """
        let message = try decoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.content, "part one\npart two")
    }

    func testChatMessageToleratesUnknownContentShape() throws {
        let json = #"{"role": "assistant", "content": 42}"#
        let message = try decoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.content)
    }

    // MARK: Workspaces

    func testWorkspaceRootDecodesStringOrObject() throws {
        let json = #"{"workspaces": ["/srv/projects", {"path": "/srv/app", "name": "App"}]}"#
        let response = try decoder().decode(WorkspacesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.workspaces?.count, 2)
        XCTAssertEqual(response.workspaces?[0].path, "/srv/projects")
        XCTAssertEqual(response.workspaces?[0].displayName, "projects")
        XCTAssertEqual(response.workspaces?[1].displayName, "App")
    }

    // MARK: Approvals

    func testPendingApprovalReadsApprovalIdOrIdKey() throws {
        let a = try decoder().decode(PendingApproval.self, from: Data(#"{"approval_id": "abc", "command": "rm -rf"}"#.utf8))
        XCTAssertEqual(a.approvalId, "abc")

        let b = try decoder().decode(PendingApproval.self, from: Data(#"{"id": "xyz"}"#.utf8))
        XCTAssertEqual(b.approvalId, "xyz")
    }

    // MARK: Cron jobs

    func testCronJobFlexibleTimestamps() throws {
        let numeric = try decoder().decode(CronJob.self, from: Data(#"{"id": "j1", "next_run_at": 1720000000.5}"#.utf8))
        XCTAssertEqual(numeric.nextRunAt, 1720000000.5)

        let iso = try decoder().decode(CronJob.self, from: Data(#"{"id": "j2", "next_run_at": "2026-07-12T10:00:00Z"}"#.utf8))
        XCTAssertNotNil(iso.nextRunAt)

        let junk = try decoder().decode(CronJob.self, from: Data(#"{"id": "j3", "next_run_at": "soon"}"#.utf8))
        XCTAssertNil(junk.nextRunAt)
    }

    func testCronJobPrefersIdOverJobId() throws {
        let job = try decoder().decode(CronJob.self, from: Data(#"{"id": "primary", "job_id": "secondary"}"#.utf8))
        XCTAssertEqual(job.jobId, "primary")
    }

    // MARK: Session summaries

    func testSessionSummarySortTimestampFallbackChain() throws {
        let json = #"{"session_id": "s1", "updated_at": 100}"#
        let session = try decoder().decode(SessionSummary.self, from: Data(json.utf8))
        XCTAssertEqual(session.sortTimestamp, 100)
        XCTAssertEqual(session.displayTitle, "Untitled session")
    }
}
