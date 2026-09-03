import XCTest
@testable import AnyTravel

final class FliggyFlightDirectClientTests: XCTestCase {
    @MainActor
    func testPublicSearchResultBecomesLiveFlightAndMergesSameFlightAcrossProviders() async throws {
        let departure = try XCTUnwrap(Self.dayFormatter.date(from: "2026-09-09"))
        let departureTime = try XCTUnwrap(Self.dateTimeFormatter.date(from: "2026-09-09 22:25"))
        let arrivalTime = try XCTUnwrap(Self.dateTimeFormatter.date(from: "2026-09-10 00:40"))
        let existing = TransportOption(
            mode: .flight,
            title: "奥凯 BK2878",
            originName: "栎社机场",
            destinationName: "滨海机场",
            direction: .outbound,
            durationMinutes: 135,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            quotes: [
                ProviderQuote(
                    provider: .qunar,
                    amountCNY: 478,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: departure,
                    note: "fixture"
                )
            ]
        )
        let client = FliggyFlightDirectClient(resultLimit: 4) { departureCode, arrivalCode, date in
            XCTAssertEqual(departureCode, "NGB")
            XCTAssertEqual(arrivalCode, "TSN")
            XCTAssertEqual(Self.dayFormatter.string(from: date), "2026-09-09")
            return FliggyFlightSearchResult(
                offers: [
                    FliggyFlightOffer(
                        price: 453,
                        airline: "奥凯",
                        flightNumber: "BK2878",
                        departureTime: "22:25",
                        arrivalTime: "00:40",
                        departureAirport: "栎社机场",
                        arrivalAirport: "滨海机场",
                        durationMinutes: 135
                    )
                ],
                lowestPrice: 453
            )
        }

        let result = try await client.enrichTransportOptions(
            [existing],
            origin: "宁波",
            destination: "天津市",
            logistics: TripLogistics(origin: "宁波", startDate: departure, travelers: 1),
            accessPoints: [],
            accommodation: nil
        )

        let flights = result.value.filter { $0.mode == .flight && $0.journeyDirection == .outbound }
        XCTAssertEqual(flights.count, 1)
        XCTAssertEqual(Set(flights[0].quotes.map(\.provider)), [.qunar, .fliggy])
        XCTAssertEqual(flights[0].quotes.first(where: { $0.provider == .fliggy })?.amountCNY, 453)
        XCTAssertEqual(result.receivedCount, 1)
    }

    @MainActor
    func testSuzhouUsesNearbyWuxiCivilAviationCode() async throws {
        let departure = try XCTUnwrap(Self.dayFormatter.date(from: "2026-09-09"))
        let client = FliggyFlightDirectClient { departureCode, arrivalCode, _ in
            XCTAssertEqual(departureCode, "NGB")
            XCTAssertEqual(arrivalCode, "WUX")
            return FliggyFlightSearchResult(offers: [], lowestPrice: 399)
        }
        let result = try await client.enrichTransportOptions(
            [],
            origin: "宁波",
            destination: "苏州",
            logistics: TripLogistics(origin: "宁波", startDate: departure, travelers: 2),
            accessPoints: [],
            accommodation: nil
        )
        XCTAssertEqual(result.value.first?.quotes.first?.priceText, "¥399起")
    }

    @MainActor
    func testParsesOnlyFlightRowsAndKeepsCurrentMinimum() throws {
        let fixture = #"""
        {
          "ret":["SUCCESS::调用成功"],
          "data":{
            "success":true,
            "lowestPrice":453,
            "items":[
              {"itemType":"DIRECT","itemDatas":[
                {"flightName":"BK2878","airlineChineseName":"奥凯","bestPrice":453,
                 "depTime":"2026-09-09 22:25","arrTime":"2026-09-10 00:40",
                 "depAirportName":"栎社机场","arrAirportName":"滨海机场","duration":135}
              ]},
              {"itemType":"ADVERTISEMENT","itemDatas":[
                {"flightName":"AD0001","bestPrice":1,"depTime":"08:00","arrTime":"09:00"}
              ]}
            ]
          }
        }
        """#
        let result = try XCTUnwrap(FliggyMTOPFlightPage.parse(data: Data(fixture.utf8)))
        XCTAssertEqual(result.lowestPrice, 453)
        XCTAssertEqual(result.offers.count, 1)
        XCTAssertEqual(result.offers[0].flightNumber, "BK2878")
        XCTAssertEqual(result.offers[0].departureTime, "22:25")
        XCTAssertEqual(result.offers[0].arrivalAirport, "滨海机场")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
