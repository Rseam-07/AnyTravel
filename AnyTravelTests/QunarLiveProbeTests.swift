import XCTest
@testable import AnyTravel

final class QunarLiveProbeTests: XCTestCase {
    @MainActor
    func testLivePublicPageReturnsAQuoteOrAnExplicitProviderState() async throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        var logistics = TripLogistics()
        logistics.startDate = try XCTUnwrap(formatter.date(from: "2026-09-09"))
        let estimate = TransportOption(
            mode: .flight,
            title: "航班抵达天津",
            originName: "宁波",
            destinationName: "天津"
        )
        let result = try await QunarFlightDirectClient(resultLimit: 3).enrichTransportOptions(
            [estimate],
            origin: "宁波",
            destination: "天津",
            logistics: logistics,
            accessPoints: [],
            accommodation: nil
        )
        let prices = result.value.flatMap(\.quotes).compactMap(\.amountCNY)
        let statuses = Set(result.issues.map(\.status))
        print("QUNAR_LIVE_PROBE prices=\(prices) statuses=\(statuses.sorted()) details=\(result.issues.compactMap(\.detail))")
        XCTAssertTrue(
            !prices.isEmpty || !statuses.isDisjoint(with: [
                "verification_required", "no_matching_quotes", "no_visible_cards", "failed"
            ])
        )
    }
}
