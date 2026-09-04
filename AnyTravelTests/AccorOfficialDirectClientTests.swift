import XCTest
@testable import AnyTravel

@MainActor
final class AccorOfficialDirectClientTests: XCTestCase {
    override func tearDown() {
        AccorOfficialURLProtocol.requestHandler = nil
        AccorOfficialURLProtocol.requestedURLs = []
        super.tearDown()
    }

    func testChineseCityReturnsSelectedDateLiveRateAndDatedBookingLink() async throws {
        AccorOfficialURLProtocol.requestHandler = { request in
            if request.url?.host?.contains("algolia.net") == true {
                let payload: [String: Any] = [
                    "hits": [[
                        "objectID": "B1K2",
                        "name": "苏州中惠雅高铂尔曼酒店",
                        "brandLabel": "铂尔曼",
                        "stars": 5,
                        "rating": ["score": 4.7],
                        "localization": [
                            "address": ["street": "相城区嘉元路188号", "city": "苏州"],
                            "gps": ["lat": 31.371, "lng": 120.615]
                        ],
                        "freeAmenities": [["label": "无线网络"]],
                        "labels": ["亲子友好"],
                        "mediaCatalog": ["1024x768": "https://example.com/pullman.jpg"]
                    ]]
                ]
                return try Self.response(for: request, payload: payload)
            }
            let payload: [String: Any] = [
                "data": [
                    "hotelOffers": [
                        "availability": ["status": "AVAILABLE"],
                        "offersSelection": [
                            "offers": [[
                                "accommodation": ["code": "SUP"],
                                "mealPlan": ["label": "含早餐"],
                                "pricing": [
                                    "main": [
                                        "amount": 974.4,
                                        "simplifiedPolicies": [
                                            "cancellation": ["label": "当日18点前免费取消"]
                                        ]
                                    ]
                                ]
                            ]]
                        ]
                    ]
                ]
            ]
            return try Self.response(for: request, payload: payload)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccorOfficialURLProtocol.self]
        let calendar = Calendar(identifier: .gregorian)
        let checkIn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let checkOut = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let capturedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)))
        let client = AccorOfficialDirectClient(
            session: URLSession(configuration: configuration),
            now: { capturedAt }
        )

        let result = try await client.searchAccommodationCatalog(
            destination: "苏州",
            logistics: TripLogistics(
                origin: "宁波",
                startDate: checkIn,
                endDate: checkOut,
                travelers: 2
            )
        )

        let hotel = try XCTUnwrap(result.value.first)
        let quote = try XCTUnwrap(hotel.quotes.first)
        XCTAssertEqual(result.receivedCount, 1)
        XCTAssertEqual(hotel.name, "苏州中惠雅高铂尔曼酒店")
        XCTAssertEqual(hotel.brand, "铂尔曼")
        XCTAssertEqual(hotel.coordinate?.latitude, 31.371)
        XCTAssertEqual(hotel.amenities, ["无线网络"])
        XCTAssertEqual(quote.provider, .propertyOfficial)
        XCTAssertEqual(quote.amountCNY, 487)
        XCTAssertEqual(quote.totalAmountCNY, 974)
        XCTAssertEqual(quote.kind, .live)
        XCTAssertEqual(quote.mealPlan, "含早餐")
        XCTAssertEqual(quote.cancellationPolicy, "当日18点前免费取消")
        XCTAssertEqual(quote.capturedAt, capturedAt)
        let bookingURL = try XCTUnwrap(quote.bookingURL?.absoluteString)
        XCTAssertTrue(bookingURL.contains("checkIn=2026-09-09"))
        XCTAssertTrue(bookingURL.contains("checkOut=2026-09-11"))
        XCTAssertTrue(AccorOfficialURLProtocol.requestedURLs.contains { $0.contains("prod_hotels_zh/query") })
    }

    private nonisolated static func response(
        for request: URLRequest,
        payload: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            try JSONSerialization.data(withJSONObject: payload)
        )
    }
}

private final class AccorOfficialURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestedURLs: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestedURLs.append(request.url?.absoluteString ?? "")
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
