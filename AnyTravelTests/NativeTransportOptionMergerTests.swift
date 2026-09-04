import XCTest
@testable import AnyTravel

@MainActor
final class NativeTransportOptionMergerTests: XCTestCase {
    func testLiveFlightRemovesRecommendedNumericFixtureAndSortsFirst() throws {
        let fixture = TransportOption(
            mode: .flight,
            title: "航班抵达天津",
            originName: "宁波",
            destinationName: "天津",
            quotes: [
                ProviderQuote(
                    provider: .anyTravelEstimate,
                    amountCNY: 320,
                    unit: .perPerson,
                    kind: .demo,
                    note: "界面样例"
                )
            ],
            isRecommended: true
        )
        let live = TransportOption(
            mode: .flight,
            title: "厦门航空 MF8123",
            originName: "栎社T2",
            destinationName: "滨海T2",
            departureTime: Date(timeIntervalSince1970: 2_000_000_000),
            quotes: [
                ProviderQuote(
                    provider: .fliggy,
                    amountCNY: 560,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: .now,
                    note: "当前搜索起价"
                )
            ]
        )

        let result = NativeFlightOptionMerger.merging(
            [live],
            into: [fixture],
            provider: .fliggy,
            direction: .outbound
        )

        XCTAssertEqual(result.map(\.title), ["厦门航空 MF8123"])
        XCTAssertTrue(try XCTUnwrap(result.first?.quotes.first).isCurrentPrice)
    }

    func testReasonableFlightDurationRanksAheadOfCheaperTwoDayConnection() {
        let longConnection = TransportOption(
            mode: .flight,
            title: "东航 MU8402",
            originName: "栎社机场",
            destinationName: "滨海机场",
            durationMinutes: 2_495,
            quotes: [
                ProviderQuote(
                    provider: .fliggy,
                    amountCNY: 530,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: .now,
                    note: "当前搜索起价"
                )
            ]
        )
        let directFlight = TransportOption(
            mode: .flight,
            title: "奥凯 BK2878",
            originName: "栎社机场",
            destinationName: "滨海机场",
            durationMinutes: 135,
            quotes: [
                ProviderQuote(
                    provider: .fliggy,
                    amountCNY: 541,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: .now,
                    note: "当前搜索起价"
                )
            ]
        )

        let result = NativeFlightOptionMerger.merging(
            [longConnection, directFlight],
            into: [],
            provider: .fliggy,
            direction: .outbound
        )

        XCTAssertEqual(result.first?.title, "奥凯 BK2878")
    }

    func testLiveRailwayRemovesRecommendedDemoFareAndSortsCurrentServiceFirst() throws {
        let fixture = TransportOption(
            mode: .train,
            title: "高铁抵达苏州",
            originName: "上海",
            destinationName: "苏州",
            quotes: [
                ProviderQuote(
                    provider: .railway12306,
                    amountCNY: 39,
                    unit: .perPerson,
                    kind: .demo,
                    note: "界面样例"
                )
            ],
            isRecommended: true
        )
        let live = TransportOption(
            mode: .train,
            title: "G7012 · 上海→苏州",
            originName: "上海站",
            destinationName: "苏州站",
            departureTime: Date(timeIntervalSince1970: 2_000_000_000),
            quotes: [
                ProviderQuote(
                    provider: .railway12306,
                    amountCNY: 45,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: .now,
                    note: "二等座有票"
                )
            ]
        )

        let result = NativeRailwayOptionMerger.merging([live], into: [fixture])

        XCTAssertEqual(result.map(\.title), ["G7012 · 上海→苏州"])
        XCTAssertTrue(try XCTUnwrap(result.first?.quotes.first).isCurrentPrice)
    }

    func testRecommendedExactStationTrainStaysAheadOfCheaperSuburbanTrain() {
        let exact = TransportOption(
            mode: .train,
            title: "G7001 · 上海→苏州",
            originName: "上海",
            destinationName: "苏州",
            durationMinutes: 25,
            quotes: [
                ProviderQuote(
                    provider: .railway12306,
                    amountCNY: 39,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: .now,
                    note: "当前票价"
                )
            ],
            isRecommended: true
        )
        let suburban = TransportOption(
            mode: .train,
            title: "C3031 · 练塘→苏州南",
            originName: "练塘",
            destinationName: "苏州南",
            durationMinutes: 10,
            quotes: [
                ProviderQuote(
                    provider: .railway12306,
                    amountCNY: 10,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: .now,
                    note: "当前票价"
                )
            ]
        )

        let result = NativeRailwayOptionMerger.merging([suburban, exact], into: [])

        XCTAssertEqual(result.first?.title, "G7001 · 上海→苏州")
    }
}
