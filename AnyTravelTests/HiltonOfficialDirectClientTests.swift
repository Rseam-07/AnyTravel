import XCTest
@testable import AnyTravel

@MainActor
final class HiltonOfficialDirectClientTests: XCTestCase {
    override func tearDown() {
        HiltonOfficialURLProtocol.requestHandler = nil
        HiltonOfficialURLProtocol.lastRequestURL = nil
        super.tearDown()
    }

    func testSearchKeepsDirectoryPriceIndicativeAndBuildsDatedOfficialLink() async throws {
        HiltonOfficialURLProtocol.requestHandler = { request in
            let payload: [String: Any] = [
                "success": true,
                "code": 200,
                "data": [
                    "hotels": [[
                        "brandCode": "HI",
                        "hotelCode": "SZVTVHI",
                        "hotelName": "苏州希尔顿酒店",
                        "minPrice": 647.13,
                        "sellingPoints": ["紧邻地铁"],
                        "tags": [["tagName": "亲子友好"]],
                        "amenities": ["freeWifi"],
                        "masterCover": ["url": "https://img.example/hilton.jpg"],
                        "location": [
                            "address": "苏州大道东275号",
                            "coordinate": ["latitude": 31.324349, "longitude": 120.735565]
                        ]
                    ]]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: payload)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HiltonOfficialURLProtocol.self]
        let calendar = Calendar(identifier: .gregorian)
        let checkIn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let checkOut = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let capturedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)))
        let client = HiltonOfficialDirectClient(
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
        let requestedURL = try XCTUnwrap(HiltonOfficialURLProtocol.lastRequestURL)
        let requestedComponents = try XCTUnwrap(URLComponents(url: requestedURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(requestedComponents.queryItems?.first(where: { $0.name == "keywords" })?.value, "苏州")
        XCTAssertEqual(result.receivedCount, 1)
        XCTAssertEqual(hotel.name, "苏州希尔顿酒店")
        XCTAssertEqual(hotel.brand, "希尔顿")
        XCTAssertEqual(hotel.coordinate?.latitude, 31.324349)
        XCTAssertEqual(hotel.tags, ["紧邻地铁", "亲子友好"])
        XCTAssertEqual(quote.provider, .propertyOfficial)
        XCTAssertEqual(quote.amountCNY, 647)
        XCTAssertEqual(quote.kind, .indicative)
        XCTAssertEqual(quote.capturedAt, capturedAt)
        let bookingURL = try XCTUnwrap(quote.bookingURL?.absoluteString)
        XCTAssertTrue(bookingURL.contains("arrivalDate=2026-09-09"))
        XCTAssertTrue(bookingURL.contains("departureDate=2026-09-11"))
        XCTAssertTrue(bookingURL.contains("room1NumAdults=2"))
    }
}

private final class HiltonOfficialURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequestURL: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequestURL = request.url
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
