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
}
