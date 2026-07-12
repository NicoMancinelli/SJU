import XCTest
@testable import Hermex

final class SSEDecodingTests: XCTestCase {
    func testTokenEvent() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "token", data: #"{"text": "hello"}"#),
            .token("hello")
        )
    }

    func testTokenEventWithMalformedPayloadYieldsEmptyToken() {
        XCTAssertEqual(SSEStream.decode(eventType: "token", data: "not json"), .token(""))
    }

    func testReasoningEvent() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "reasoning", data: #"{"text": "thinking"}"#),
            .reasoning("thinking")
        )
    }

    func testInterimAssistantEvent() {
        XCTAssertEqual(
            SSEStream.decode(
                eventType: "interim_assistant",
                data: #"{"text": "partial answer", "already_streamed": true}"#
            ),
            .interimAssistant(text: "partial answer", alreadyStreamed: true)
        )
    }

    func testInterimAssistantDefaultsAlreadyStreamedToFalse() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "interim_assistant", data: #"{"text": "t"}"#),
            .interimAssistant(text: "t", alreadyStreamed: false)
        )
    }

    func testToolEvents() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "tool", data: #"{"name": "bash", "preview": "ls -la"}"#),
            .toolStarted(name: "bash", preview: "ls -la")
        )
        XCTAssertEqual(
            SSEStream.decode(eventType: "tool_complete", data: #"{"name": "bash", "is_error": true}"#),
            .toolCompleted(name: "bash", preview: nil, isError: true)
        )
    }

    func testToolEventWithoutNameFallsBackToGenericName() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "tool", data: "{}"),
            .toolStarted(name: "tool", preview: nil)
        )
    }

    func testTitleEventIgnoredWhenEmpty() {
        XCTAssertEqual(SSEStream.decode(eventType: "title", data: "{}"), .ignored)
        XCTAssertEqual(
            SSEStream.decode(eventType: "title", data: #"{"title": "My Session"}"#),
            .title("My Session")
        )
    }

    func testPendingSteerLeftover() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "pending_steer_leftover", data: #"{"text": "do this next"}"#),
            .pendingSteerLeftover("do this next")
        )
    }

    func testTerminalFrames() {
        XCTAssertEqual(SSEStream.decode(eventType: "stream_end", data: ""), .streamEnd)
        XCTAssertEqual(SSEStream.decode(eventType: "cancel", data: ""), .cancelled)
        XCTAssertEqual(SSEStream.decode(eventType: "done", data: "{}"), .done)
    }

    func testErrorEventPrefersErrorFieldThenMessage() {
        XCTAssertEqual(
            SSEStream.decode(eventType: "error", data: #"{"error": "boom"}"#),
            .error("boom")
        )
        XCTAssertEqual(
            SSEStream.decode(eventType: "apperror", data: #"{"message": "bad state"}"#),
            .error("bad state")
        )
        XCTAssertEqual(
            SSEStream.decode(eventType: "error", data: "{}"),
            .error("The stream returned an error.")
        )
    }

    func testUnknownEventIsIgnored() {
        XCTAssertEqual(SSEStream.decode(eventType: "heartbeat", data: "{}"), .ignored)
    }
}
