import XCTest
@testable import AnyTravel

final class QunarFlightDirectClientTests: XCTestCase {
    @MainActor
    func testNormalWebSessionProducesOutboundFlightAndReturnPageMinimum() async throws {
        let client = QunarFlightDirectClient(resultLimit: 4) { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let departure = components?.queryItems?.first { $0.name == "depCity" }?.value
            let arrival = components?.queryItems?.first { $0.name == "arrCity" }?.value
            if departure == "宁波", arrival == "无锡" {
                return QunarFlightPageSnapshot(
                    cards: [
                        QunarFlightPageSnapshot.Card(
                            priceText: "¥399起",
                            departureTime: "08:15",
                            arrivalTime: "10:02",
                            departurePlace: "栎社T2",
                            arrivalPlace: "苏南硕放T2",
                            airline: "东方航空",
                            flightNumber: "MU6251",
                            durationText: "1小时47分",
                            detailText: "经济舱起价"
                        )
                    ],
                    responseBodies: [],
                    pageText: "宁波到无锡航班",
                    pageURL: url
                )
            }
            XCTAssertEqual(departure, "无锡")
            XCTAssertEqual(arrival, "宁波")
            return QunarFlightPageSnapshot(
                cards: [],
                responseBodies: [#"{"data":{"calendar":{"minPrice":"¥420"}}}"#],
                pageText: "无锡到宁波航班",
                pageURL: url
            )
        }

        var logistics = TripLogistics()
        logistics.startDate = Date(timeIntervalSince1970: 2_000_000_000)
        logistics.endDate = Date(timeIntervalSince1970: 2_000_086_400)
        logistics.travelers = 2
        let outboundEstimate = TransportOption(
            mode: .flight,
            title: "航班抵达苏州",
            originName: "宁波",
            destinationName: "苏州",
            direction: .outbound,
            quotes: [
                ProviderQuote(provider: .ctrip, unit: .perPerson, kind: .checkOnProvider, note: "待查询"),
                ProviderQuote(provider: .qunar, unit: .perPerson, kind: .checkOnProvider, note: "待查询")
            ]
        )
        let returnEstimate = TransportOption(
            mode: .flight,
            title: "航班返回宁波",
            originName: "苏州",
            destinationName: "宁波",
            direction: .returnTrip,
            quotes: [
                ProviderQuote(provider: .qunar, unit: .perPerson, kind: .checkOnProvider, note: "待查询")
            ]
        )
        let airport = AccessPoint(
            name: "苏南硕放国际机场",
            coordinate: Coordinate(latitude: 31.494, longitude: 120.429),
            kind: .airport
        )

        let result = try await client.enrichTransportOptions(
            [outboundEstimate, returnEstimate],
            origin: "宁波市",
            destination: "苏州市",
            logistics: logistics,
            accessPoints: [airport],
            accommodation: nil
        )

        let outbound = try XCTUnwrap(result.value.first {
            $0.mode == .flight && $0.journeyDirection == .outbound
        })
        let returnTrip = try XCTUnwrap(result.value.first {
            $0.mode == .flight && $0.journeyDirection == .returnTrip
        })
        XCTAssertTrue(outbound.title.contains("MU6251"))
        XCTAssertEqual(outbound.durationMinutes, 107)
        XCTAssertEqual(outbound.arrivalAccessPoint?.name, "苏南硕放国际机场")
        XCTAssertEqual(outbound.quotes.first?.provider, .qunar)
        XCTAssertEqual(outbound.quotes.first?.amountCNY, 399)
        XCTAssertEqual(outbound.quotes.first?.kind, .live)
        XCTAssertFalse(outbound.quotes.contains { $0.provider == .ctrip })
        XCTAssertTrue(returnTrip.title.contains("当日起价"))
        XCTAssertEqual(returnTrip.quotes.first?.amountCNY, 420)
        XCTAssertEqual(returnTrip.quotes.first?.displayPriceText, "¥420起")
        XCTAssertEqual(result.receivedCount, 2)
        XCTAssertTrue(result.issues.isEmpty)
    }

    @MainActor
    func testDefaultClientDoesNotOpenQunarWithoutExplicitlySavedSession() async throws {
        let suiteName = "QunarFlightDirectClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertFalse(ProviderSessionStore.hasSavedSession(.qunar, defaults: defaults))

        var logistics = TripLogistics()
        logistics.startDate = Date(timeIntervalSince1970: 2_000_000_000)
        let estimate = TransportOption(
            mode: .flight,
            title: "航班抵达天津",
            originName: "宁波",
            destinationName: "天津",
            direction: .outbound
        )

        // The production client reads the standard store. Clear only this provider's
        // marker so the assertion remains deterministic without touching WebKit data.
        let standard = UserDefaults.standard
        let previous = standard.data(forKey: ProviderSessionStore.storageKey)
        standard.removeObject(forKey: ProviderSessionStore.storageKey)
        defer {
            if let previous { standard.set(previous, forKey: ProviderSessionStore.storageKey) }
        }

        let result = try await QunarFlightDirectClient().enrichTransportOptions(
            [estimate],
            origin: "宁波",
            destination: "天津",
            logistics: logistics,
            accessPoints: [],
            accommodation: nil
        )

        XCTAssertEqual(result.value, [estimate])
        XCTAssertEqual(result.receivedCount, 0)
        XCTAssertTrue(result.issues.isEmpty)
    }

    @MainActor
    func testCapturedResponseParsesNestedFlightAndDeduplicatesIt() async throws {
        let response = #"{"data":{"list":[{"depTime":"2026-09-09 09:10","arrTime":"11:35","depAirport":"栎社T2","arrAirport":"滨海T2","name":"厦门航空","binfo":"MF8123","totalDuration":145,"minPrice":560},{"depTime":"2026-09-09 09:10","arrTime":"11:35","depAirport":"栎社T2","arrAirport":"滨海T2","name":"厦门航空","binfo":"MF8123","totalDuration":145,"minPrice":560}]}}"#
        let client = QunarFlightDirectClient { url in
            QunarFlightPageSnapshot(
                cards: [],
                responseBodies: [response],
                pageText: "",
                pageURL: url
            )
        }
        var logistics = TripLogistics()
        logistics.startDate = Date(timeIntervalSince1970: 2_000_000_000)

        let result = try await client.enrichTransportOptions(
            [],
            origin: "宁波",
            destination: "天津",
            logistics: logistics,
            accessPoints: [],
            accommodation: nil
        )

        XCTAssertEqual(result.value.count, 1)
        XCTAssertEqual(result.value.first?.title, "厦门航空 MF8123 · 栎社T2→滨海T2")
        XCTAssertEqual(result.value.first?.quotes.first?.amountCNY, 560)
        XCTAssertEqual(result.receivedCount, 1)
    }
}
