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

    func testParsesAnOpenTravelRequest() throws {
        let intent = parser.parse("从上海出发，两个人去苏州玩4天，5月2日到5月5日，优先高铁，酒店每晚不超过600元并按价格最低排序，帮我规划")

        XCTAssertEqual(intent.origin, "上海")
        XCTAssertEqual(intent.destination, "苏州")
        XCTAssertEqual(intent.travelers, 2)
        XCTAssertEqual(intent.dayCount, 4)
        XCTAssertEqual(intent.longDistanceMode, .train)
        XCTAssertEqual(intent.accommodationMaxPrice, 600)
        XCTAssertEqual(intent.accommodationSort, .lowestPrice)
        XCTAssertTrue(intent.shouldGeneratePlan)
        XCTAssertNotNil(intent.startDate)
        XCTAssertNotNil(intent.endDate)
    }
}

@MainActor
final class PlannerDateAdjustmentTests: XCTestCase {
    func testDayAndDateControlsCanMoveBackwardAndStaySynchronized() throws {
        let model = PlannerViewModel()
        model.draft.dayCount = 4
        model.setDatesEnabled(true)
        let originalStart = try XCTUnwrap(model.draft.logistics.startDate)
        let originalEnd = try XCTUnwrap(model.draft.logistics.endDate)

        model.adjustStartDate(by: -1)
        XCTAssertLessThan(model.draft.logistics.startDate ?? originalStart, originalStart)
        XCTAssertLessThan(model.draft.logistics.endDate ?? originalEnd, originalEnd)

        model.adjustDayCount(by: -1)
        XCTAssertEqual(model.draft.dayCount, 3)
        let start = try XCTUnwrap(model.draft.logistics.startDate)
        let end = try XCTUnwrap(model.draft.logistics.endDate)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: start, to: end).day, 2)
    }

    func testAccommodationFiltersUseRealPricesAndDistance() {
        let model = PlannerViewModel()
        model.accommodations = [
            AccommodationOption(
                name: "近处酒店",
                address: "近处",
                coordinate: Coordinate(latitude: 31.3, longitude: 120.6),
                attractionDistanceMeters: 1_200,
                quotes: [ProviderQuote(provider: .rollingGo, amountCNY: 480, unit: .perNight, kind: .live, note: "实时价")]
            ),
            AccommodationOption(
                name: "远处酒店",
                address: "远处",
                coordinate: Coordinate(latitude: 31.4, longitude: 120.7),
                attractionDistanceMeters: 8_000,
                quotes: [ProviderQuote(provider: .rollingGo, amountCNY: 880, unit: .perNight, kind: .live, note: "实时价")]
            )
        ]

        model.accommodationMaxNightlyPrice = 600
        model.accommodationMaxAttractionDistanceMeters = 2_000
        XCTAssertEqual(model.filteredAccommodations.map(\.name), ["近处酒店"])
    }
}
