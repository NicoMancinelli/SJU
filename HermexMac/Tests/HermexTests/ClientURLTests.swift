import XCTest
@testable import Hermex

final class ClientURLTests: XCTestCase {
    func testChatStreamURL() {
        let client = APIClient(baseURL: URL(string: "https://hermes.example.com")!)
        let url = client.chatStreamURL(streamID: "abc123")
        XCTAssertEqual(url.absoluteString, "https://hermes.example.com/api/chat/stream?stream_id=abc123")
    }

    func testChatStreamURLWithReplay() {
        let client = APIClient(baseURL: URL(string: "https://hermes.example.com")!)
        let url = client.chatStreamURL(streamID: "abc", replayAfterSeq: 41)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "replay", value: "1")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "after_seq", value: "41")))
    }

    func testReplaySequenceClampedToZero() {
        let client = APIClient(baseURL: URL(string: "https://hermes.example.com")!)
        let url = client.chatStreamURL(streamID: "abc", replayAfterSeq: -5)
        XCTAssertTrue(url.absoluteString.contains("after_seq=0"))
    }

    func testBaseURLWithSubpathIsPreserved() {
        let client = APIClient(baseURL: URL(string: "https://example.com/hermes")!)
        let url = client.chatStreamURL(streamID: "s")
        XCTAssertEqual(url.path, "/hermes/api/chat/stream")
    }

    func testBaseURLWithTrailingSlash() {
        let client = APIClient(baseURL: URL(string: "http://localhost:8787/")!)
        let url = client.chatStreamURL(streamID: "s")
        XCTAssertEqual(url.path, "/api/chat/stream")
        XCTAssertEqual(url.port, 8787)
    }
}
