import XCTest
@testable import AnyTravel

final class PricingBackendClientTests: XCTestCase {
    override func tearDown() {
        PricingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testLiveAccommodationResponseIsMergedAndKeepsDiagnosticsVisible() async throws {
        let hotelID = UUID()
        let capturedAt = "2026-08-31T12:00:00Z"
        PricingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/quotes/accommodations")
            let body = Data("""
            {
              "quotes": [{
                "hotelID": "\(hotelID.uuidString)",
                "hotelName": "测试酒店",
                "provider": "rollinggo",
                "amountCNY": 488,
                "unit": "perNight",
                "kind": "live",
                "capturedAt": "\(capturedAt)",
                "bookingURL": "https://example.com/book",
                "note": "实时展示价"
              }],
              "diagnostics": [{"provider":"ctrip","status":"disabled"}],
              "capturedAt": "\(capturedAt)",
              "cached": false
            }
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeClient()
        let hotel = AccommodationOption(
            id: hotelID,
            name: "测试酒店",
            address: "苏州",
            coordinate: Coordinate(latitude: 31.3, longitude: 120.6),
            attractionDistanceMeters: 500
        )

        let result = try await context.client.enrichAccommodationQuotes(
            [hotel],
            destination: "苏州",
            logistics: datedLogistics()
        )

        XCTAssertEqual(result.receivedCount, 1)
        XCTAssertEqual(result.value.first?.quotes.first?.amountCNY, 488)
        XCTAssertEqual(result.value.first?.quotes.first?.provider, .rollingGo)
        XCTAssertEqual(result.issues.first?.status, "disabled")
        XCTAssertEqual(result.issues.first?.message, "携程尚未在报价节点启用")
        XCTAssertFalse(result.isCached)
    }

    @MainActor
    func testHTTPFailureIsReportedInsteadOfSilentlyReturningOldCards() async throws {
        PricingURLProtocol.requestHandler = { request in
            let body = Data(#"{"error":"rate_limit"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeClient()
        let hotel = AccommodationOption(
            name: "测试酒店",
            address: "苏州",
            coordinate: Coordinate(latitude: 31.3, longitude: 120.6),
            attractionDistanceMeters: 500
        )

        do {
            _ = try await context.client.enrichAccommodationQuotes(
                [hotel],
                destination: "苏州",
                logistics: datedLogistics()
            )
            XCTFail("HTTP failure should be surfaced")
        } catch let error as PricingBackendError {
            XCTAssertEqual(error, .httpFailure(statusCode: 429, message: "rate_limit"))
        }
    }

    @MainActor
    private func makeClient() throws -> (client: PricingBackendClient, defaults: UserDefaults) {
        let suiteName = "AnyTravel.PricingBackendClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("https://quotes.example/", forKey: PricingBackendClient.serviceURLDefaultsKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PricingURLProtocol.self]
        return (PricingBackendClient(session: URLSession(configuration: configuration), defaults: defaults), defaults)
    }

    @MainActor
    private func datedLogistics() -> TripLogistics {
        var logistics = TripLogistics()
        logistics.startDate = Date(timeIntervalSince1970: 2_000_000_000)
        logistics.endDate = Date(timeIntervalSince1970: 2_000_086_400)
        return logistics
    }
}

private final class PricingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
