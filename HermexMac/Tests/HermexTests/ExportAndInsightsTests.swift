import XCTest
@testable import Hermex

final class ExportAndInsightsTests: XCTestCase {
    func testContentDispositionFilenameParsing() {
        XCTAssertEqual(
            APIClient.filename(fromContentDisposition: #"attachment; filename="hermes-abc.json""#),
            "hermes-abc.json"
        )
        XCTAssertEqual(
            APIClient.filename(fromContentDisposition: "attachment; filename=plain.html; size=12"),
            "plain.html"
        )
        // Path components must not escape the basename.
        XCTAssertEqual(
            APIClient.filename(fromContentDisposition: #"attachment; filename="../../etc/passwd""#),
            "passwd"
        )
        XCTAssertNil(APIClient.filename(fromContentDisposition: "attachment"))
        XCTAssertNil(APIClient.filename(fromContentDisposition: #"attachment; filename="""#))
    }

    func testInsightsResponseDecoding() throws {
        let json = """
        {
          "period_days": 30,
          "total_sessions": 12,
          "total_messages": 340,
          "total_input_tokens": 1000,
          "total_output_tokens": 2000,
          "total_tokens": 3000,
          "total_cost": 1.234567,
          "total_cache_hit_percent": 61.5,
          "models": [
            {"model": "claude", "sessions": 10, "input_tokens": 900, "output_tokens": 1800,
             "total_tokens": 2700, "cost": 1.1, "cache_hit_percent": 60, "token_share": 90, "cost_share": 89}
          ],
          "daily_tokens": [
            {"date": "2026-07-11", "input_tokens": 500, "output_tokens": 700, "sessions": 3, "cost": 0.5}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let insights = try decoder.decode(InsightsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(insights.totalSessions, 12)
        XCTAssertEqual(insights.models?.first?.model, "claude")
        XCTAssertEqual(insights.dailyTokens?.first?.totalTokens, 1200)
        XCTAssertEqual(insights.totalCacheHitPercent, 61.5)
    }
}
