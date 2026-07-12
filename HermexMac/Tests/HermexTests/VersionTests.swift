import XCTest
@testable import Hermex

final class VersionTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(UpdateChecker.isVersion("1.0.1", newerThan: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.1", newerThan: "1.0.9"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.0.1", newerThan: "1.0.0"))
    }

    func testNotNewerVersions() {
        XCTAssertFalse(UpdateChecker.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.9.9", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", newerThan: "1.0.0"))
    }

    func testNonNumericComponentsCompareAsZero() {
        XCTAssertFalse(UpdateChecker.isVersion("abc", newerThan: "0.0.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.0", newerThan: "abc"))
    }
}
