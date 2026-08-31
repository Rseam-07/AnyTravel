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
    func testOutboundAndReturnRailOptionsStayIndependent() async throws {
        let capturedAt = "2026-08-31T12:00:00Z"
        PricingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/quotes/transport")
            var requestBody = request.httpBody ?? Data()
            if requestBody.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    requestBody.append(buffer, count: count)
                }
            }
            XCTAssertFalse(requestBody.isEmpty)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            XCTAssertEqual(json["origin"] as? String, "上海")
            XCTAssertEqual(json["destination"] as? String, "苏州")
            XCTAssertNotNil(json["departureDate"] as? String)
            XCTAssertNotNil(json["returnDate"] as? String)

            let body = Data("""
            {
              "options": [
                {
                  "provider": "12306",
                  "mode": "train",
                  "direction": "outbound",
                  "serviceNumber": "G7001",
                  "originName": "上海",
                  "destinationName": "苏州",
                  "departureTime": "2026-08-31T01:00:00Z",
                  "arrivalTime": "2026-08-31T01:30:00Z",
                  "durationMinutes": 30,
                  "amountCNY": 40,
                  "fareName": "二等座",
                  "availability": "有票",
                  "bookingURL": "https://example.com/outbound",
                  "capturedAt": "\(capturedAt)",
                  "note": "去程实时"
                },
                {
                  "provider": "12306",
                  "mode": "train",
                  "direction": "return",
                  "serviceNumber": "G7028",
                  "originName": "苏州",
                  "destinationName": "上海",
                  "departureTime": "2026-09-01T09:00:00Z",
                  "arrivalTime": "2026-09-01T09:32:00Z",
                  "durationMinutes": 32,
                  "amountCNY": 50,
                  "fareName": "二等座",
                  "availability": "有票",
                  "bookingURL": "https://example.com/return",
                  "capturedAt": "\(capturedAt)",
                  "note": "返程实时"
                }
              ],
              "diagnostics": [{"provider":"12306","status":"ok"}],
              "capturedAt": "\(capturedAt)",
              "cached": false
            }
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeClient()
        let station = AccessPoint(
            name: "苏州站",
            coordinate: Coordinate(latitude: 31.33, longitude: 120.61),
            kind: .rail
        )
        let estimate = TransportOption(
            mode: .train,
            title: "高铁抵达苏州",
            originName: "上海",
            destinationName: "苏州",
            arrivalAccessPoint: station,
            isRecommended: true
        )

        let result = try await context.client.enrichTransportOptions(
            [estimate],
            origin: "上海",
            destination: "苏州",
            logistics: datedLogistics(),
            accessPoints: [station],
            accommodation: nil
        )

        XCTAssertEqual(result.receivedCount, 2)
        XCTAssertEqual(result.value.filter { $0.journeyDirection == .outbound }.count, 1)
        XCTAssertEqual(result.value.filter { $0.journeyDirection == .returnTrip }.count, 1)
        XCTAssertEqual(result.value.first(where: { $0.journeyDirection == .outbound })?.title, "G7001 · 上海→苏州")
        XCTAssertEqual(result.value.first(where: { $0.journeyDirection == .returnTrip })?.title, "G7028 · 苏州→上海")
        XCTAssertEqual(result.value.first(where: { $0.journeyDirection == .returnTrip })?.quotes.first?.amountCNY, 50)
    }

    @MainActor
    func testPartialOutboundRefreshKeepsTheSavedReturnChoiceVisible() async throws {
        let capturedAt = "2026-08-31T12:00:00Z"
        PricingURLProtocol.requestHandler = { request in
            let body = Data("""
            {
              "options": [{
                "provider": "12306",
                "mode": "train",
                "direction": "outbound",
                "serviceNumber": "G7001",
                "originName": "上海",
                "destinationName": "苏州",
                "departureTime": "2026-08-31T01:00:00Z",
                "arrivalTime": "2026-08-31T01:30:00Z",
                "durationMinutes": 30,
                "amountCNY": 40,
                "fareName": "二等座",
                "availability": "有票",
                "capturedAt": "\(capturedAt)",
                "note": "去程实时"
              }],
              "diagnostics": [{"provider":"12306","status":"failed","detail":"返程查询失败"}],
              "capturedAt": "\(capturedAt)",
              "cached": false
            }
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeClient()
        let outboundEstimate = TransportOption(
            mode: .train,
            title: "高铁抵达苏州",
            originName: "上海",
            destinationName: "苏州"
        )
        let savedReturn = TransportOption(
            mode: .train,
            title: "G7028 · 苏州→上海",
            originName: "苏州",
            destinationName: "上海",
            direction: .returnTrip,
            quotes: [ProviderQuote(provider: .railway12306, amountCNY: 50, unit: .perPerson, kind: .live, note: "上次保存")]
        )

        let result = try await context.client.enrichTransportOptions(
            [outboundEstimate, savedReturn],
            origin: "上海",
            destination: "苏州",
            logistics: datedLogistics(),
            accessPoints: [],
            accommodation: nil
        )

        XCTAssertEqual(result.value.filter { $0.journeyDirection == .outbound }.count, 1)
        XCTAssertEqual(result.value.first(where: { $0.journeyDirection == .returnTrip })?.id, savedReturn.id)
        XCTAssertEqual(result.value.first(where: { $0.journeyDirection == .returnTrip })?.quotes.first?.amountCNY, 50)
        XCTAssertEqual(result.issues.first?.detail, "返程查询失败")
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
