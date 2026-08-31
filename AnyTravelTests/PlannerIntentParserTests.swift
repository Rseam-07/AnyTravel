import XCTest
@testable import AnyTravel

final class PlannerIntentParserTests: XCTestCase {
    private let parser = PlannerIntentParser()

    func testParsesPaceAndRemovesAnInterest() {
        let intent = parser.parse("不要博物馆，轻松一点")

        XCTAssertEqual(intent.pace, .relaxed)
        XCTAssertEqual(intent.removedInterests, [.culture])
        XCTAssertTrue(intent.addedInterests.isEmpty)
        XCTAssertNil(intent.excludedPlaceTerm)
    }

    func testParsesDaysBudgetAndTransport() {
        let intent = parser.parse("改成4天，预算每人5000元，公交优先")

        XCTAssertEqual(intent.dayCount, 4)
        XCTAssertEqual(intent.budgetPerPerson, 5_000)
        XCTAssertEqual(intent.travelMode, .transit)
    }

    func testClampsRequestedDaysToSupportedRange() {
        XCTAssertEqual(parser.parse("安排20天").dayCount, 7)
        XCTAssertEqual(parser.parse("安排0天").dayCount, 1)
    }

    func testExtractsAnUnknownPlaceForRemoval() {
        let intent = parser.parse("去掉拙政园")

        XCTAssertEqual(intent.excludedPlaceTerm, "拙政园")
        XCTAssertTrue(intent.removedInterests.isEmpty)
    }

    func testUnrecognizedTextDoesNotPretendToChangeThePlan() {
        XCTAssertFalse(parser.parse("天气怎么样").isRecognized)
    }
}
