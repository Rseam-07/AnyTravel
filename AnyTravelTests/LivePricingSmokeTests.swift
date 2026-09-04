import XCTest
@testable import AnyTravel

@MainActor
final class LivePricingSmokeTests: XCTestCase {
    private func requireLiveRun() throws {
        #if ANYTRAVEL_LIVE_TESTS
        return
        #else
        guard ProcessInfo.processInfo.environment["ANYTRAVEL_RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live pricing smoke tests are opt-in")
        }
        #endif
    }

    func testEmbeddedRollingGoReturnsCurrentlyPricedHotels() async throws {
        try requireLiveRun()
        XCTAssertFalse(EmbeddedServiceConfiguration.rollingGoAPIKey.isEmpty)
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let end = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: .now))
        let result = try await RollingGoDirectClient().searchAccommodationCatalog(
            destination: "苏州",
            logistics: TripLogistics(origin: "上海", startDate: start, endDate: end, travelers: 2),
            size: 10
        )
        XCTAssertGreaterThan(result.value.count, 0)
        XCTAssertTrue(result.value.contains { $0.quotes.contains { $0.kind == .live && $0.amountCNY != nil } })
    }

    func testPublicRailwaySearchReturnsCurrentTimetableAndFare() async throws {
        try requireLiveRun()
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let result = try await Railway12306DirectClient(resultLimit: 4).enrichTransportOptions(
            [],
            origin: "上海",
            destination: "苏州",
            logistics: TripLogistics(origin: "上海", startDate: start, travelers: 2),
            accessPoints: [
                AccessPoint(
                    name: "苏州站",
                    coordinate: Coordinate(latitude: 31.329, longitude: 120.607),
                    kind: .rail
                )
            ],
            accommodation: nil
        )
        let trains = result.value.filter { $0.mode == .train && $0.journeyDirection == .outbound }
        XCTAssertGreaterThan(trains.count, 0)
        XCTAssertTrue(trains.contains { $0.quotes.contains { $0.kind == .live && $0.amountCNY != nil } })
    }

    func testPublicFlightSearchReturnsCurrentFare() async throws {
        try requireLiveRun()
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let result = try await FliggyFlightDirectClient(resultLimit: 4).enrichTransportOptions(
            [],
            origin: "宁波",
            destination: "天津",
            logistics: TripLogistics(origin: "宁波", startDate: start, travelers: 1),
            accessPoints: [],
            accommodation: nil
        )
        let flights = result.value.filter { $0.mode == .flight && $0.journeyDirection == .outbound }
        XCTAssertGreaterThan(flights.count, 0)
        XCTAssertTrue(flights.contains { $0.quotes.contains { $0.kind == .live && $0.amountCNY != nil } })
    }
}
