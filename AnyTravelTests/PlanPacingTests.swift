import XCTest
@testable import AnyTravel

@MainActor
final class PlanPacingTests: XCTestCase {
    private let service = PlanPacingService()

    func testBusyThreeDayPlanSuggestsFourDays() {
        let days = makeDays(counts: [5, 1, 1])

        let result = service.assess(days: days, pace: .full)

        XCTAssertEqual(result.level, .rushed)
        XCTAssertEqual(result.overloadedDayIndices, [0])
        XCTAssertEqual(result.suggestedDayCount, 4)
        XCTAssertTrue(result.canRelax)
    }

    func testRelaxingPreservesEveryStopAndOriginalOrder() {
        let days = makeDays(counts: [5, 1, 1])
        let originalIDs = days.flatMap(\.stops).map(\.id)

        let result = service.makeRelaxedItinerary(from: days, pace: .full)

        XCTAssertEqual(result.days.map { $0.stops.count }, [2, 2, 2, 1])
        XCTAssertEqual(result.days.flatMap(\.stops).map(\.id), originalIDs)
        XCTAssertFalse(result.stillBusy)
    }

    func testLongCityTravelAddsOneDayWhenThereAreEnoughStops() {
        let days = makeDays(counts: [2, 2, 1])

        let result = service.assess(
            days: days,
            travelMinutesByDay: [1: 95],
            pace: .relaxed
        )

        XCTAssertEqual(result.longTravelDayIndices, [1])
        XCTAssertEqual(result.suggestedDayCount, 4)
    }

    func testSevenDayLimitReportsThatThePlanIsStillBusy() {
        let days = makeDays(counts: [15])

        let result = service.makeRelaxedItinerary(from: days, pace: .full)

        XCTAssertEqual(result.days.count, 7)
        XCTAssertTrue(result.stillBusy)
        XCTAssertEqual(result.days.flatMap(\.stops).count, 15)
    }

    private func makeDays(counts: [Int]) -> [ItineraryDay] {
        var ordinal = 0
        return counts.enumerated().map { dayIndex, count in
            let stops = (0..<count).map { _ in
                defer { ordinal += 1 }
                return TravelPlace(
                    name: "地点\(ordinal)",
                    address: "测试地址",
                    coordinate: Coordinate(latitude: 31 + Double(ordinal) / 1_000, longitude: 120.6),
                    interest: .culture
                )
            }
            return ItineraryDay(index: dayIndex, stops: stops)
        }
    }
}
