import XCTest
@testable import AnyTravel

@MainActor
final class AMapPlaceClientTests: XCTestCase {
    override func tearDown() {
        AMapURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testDecodesOnlyAResponseWithExplicitCoordinateProvenance() async throws {
        AMapURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/places/search")
            let body = Data(#"{"places":[{"name":"拙政园","address":"东北街178号","coordinate":{"latitude":31.3284,"longitude":120.6205}}],"source":"AMap Web Service","sourceCRS":"GCJ-02","outputCRS":"WGS84 approximate inverse","capturedAt":"2026-08-31T12:00:00.000Z"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = try makeClient()

        let places = try await client.search(keywords: "园林", city: "苏州", interest: .gardens)

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "拙政园")
        XCTAssertEqual(places.first?.source, "高德地图 · Web服务")
    }

    func testSurfacesPlatformMismatchInsteadOfReturningEmptySuccess() async throws {
        AMapURLProtocol.requestHandler = { request in
            let body = Data(#"{"error":"amap_key_platform_mismatch","message":"当前 Key 不是高德 Web 服务 Key"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = try makeClient()

        do {
            _ = try await client.search(keywords: "园林", city: "苏州", interest: .gardens)
            XCTFail("Platform mismatch must be visible to callers")
        } catch let error as AMapPlaceClientError {
            XCTAssertEqual(
                error,
                .httpFailure(statusCode: 422, message: "当前 Key 不是高德 Web 服务 Key")
            )
        }
    }

    func testFallsBackToEmbeddedWebServiceKeyWithoutCompanion() async throws {
        AMapURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "restapi.amap.com")
            XCTAssertEqual(request.url?.path, "/v5/place/text")
            XCTAssertEqual(AMapURLProtocol.queryValue(named: "key", in: request), "amap-test-key")
            XCTAssertEqual(AMapURLProtocol.queryValue(named: "region", in: request), "苏州")
            XCTAssertEqual(AMapURLProtocol.queryValue(named: "keywords", in: request), "热门景点")
            let body = Data(#"{"status":"1","info":"OK","infocode":"10000","pois":[{"name":"拙政园","address":"东北街178号","location":"120.625,31.324","business":{"rating":"4.8","opentime_today":"07:30-17:30","opentime_week":"周一至周日"}}]}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let suiteName = "AnyTravel.AMapPlaceClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AMapURLProtocol.self]
        let client = AMapPlaceClient(
            session: URLSession(configuration: configuration),
            defaults: defaults,
            directAPIKey: { "amap-test-key" }
        )

        let places = try await client.search(
            keywords: "热门景点",
            city: "苏州",
            interest: .gardens
        )

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "拙政园")
        XCTAssertEqual(places.first?.source, "高德地图 · Web服务直连")
        XCTAssertEqual(places.first?.popularity?.rating, 4.8)
        XCTAssertNotEqual(places.first?.coordinate.longitude, 120.625)
    }

    private func makeClient() throws -> AMapPlaceClient {
        let suiteName = "AnyTravel.AMapPlaceClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("https://companion.example/", forKey: PricingBackendClient.serviceURLDefaultsKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AMapURLProtocol.self]
        return AMapPlaceClient(session: URLSession(configuration: configuration), defaults: defaults)
    }
}

private final class AMapURLProtocol: URLProtocol, @unchecked Sendable {
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

    nonisolated static func queryValue(named name: String, in request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
