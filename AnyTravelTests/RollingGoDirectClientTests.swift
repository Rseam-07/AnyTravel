import XCTest
@testable import AnyTravel

@MainActor
final class RollingGoDirectClientTests: XCTestCase {
    override func tearDown() {
        RollingGoURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSearchMapsSSEHotelAndConvertsStayTotalToNightlyPrice() async throws {
        RollingGoURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://mcp.rollinggo.cn/mcp")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer rolling-test-key")
            let requestBody = try RollingGoURLProtocol.bodyData(from: request)
            let requestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            let parameters = try XCTUnwrap(requestJSON["params"] as? [String: Any])
            XCTAssertEqual(parameters["name"] as? String, "searchHotels")

            let hotelPayload: [String: Any] = [
                "hotelInformationList": [[
                    "hotelId": 81001,
                    "bookingUrl": "https://example.com/hotel/81001",
                    "name": "苏州河畔旅居",
                    "brand": "测试品牌",
                    "address": "苏州市姑苏区",
                    "latitude": 31.32,
                    "longitude": 120.62,
                    "starRating": 4.5,
                    "price": [
                        "message": "2晚总价",
                        "hasPrice": true,
                        "currency": "CNY",
                        "lowestPrice": 224
                    ],
                    "description": "<p>临河而居</p>",
                    "hotelAmenities": ["Wi-Fi", "早餐"],
                    "tags": ["近景点"]
                ]]
            ]
            let hotelData = try JSONSerialization.data(withJSONObject: hotelPayload)
            let hotelText = try XCTUnwrap(String(data: hotelData, encoding: .utf8))
            let outer: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "result": ["content": [["type": "text", "text": hotelText]]]
            ]
            let outerData = try JSONSerialization.data(withJSONObject: outer)
            let outerText = try XCTUnwrap(String(data: outerData, encoding: .utf8))
            let body = Data("event: message\ndata: \(outerText)\n\n".utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["content-type": "text/event-stream"]
                )!,
                body
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RollingGoURLProtocol.self]
        let client = RollingGoDirectClient(
            session: URLSession(configuration: configuration),
            apiKey: { "rolling-test-key" }
        )
        let calendar = Calendar(identifier: .gregorian)
        let checkIn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)))
        let checkOut = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12)))

        let result = try await client.searchAccommodationCatalog(
            destination: "苏州",
            logistics: TripLogistics(
                origin: "上海",
                startDate: checkIn,
                endDate: checkOut,
                travelers: 2
            ),
            size: 10
        )

        XCTAssertEqual(result.value.count, 1)
        XCTAssertEqual(result.receivedCount, 1)
        XCTAssertEqual(result.value.first?.name, "苏州河畔旅居")
        XCTAssertEqual(result.value.first?.amountCNY, 112)
        XCTAssertEqual(result.value.first?.quotes.first?.kind, .live)
        XCTAssertEqual(result.value.first?.quotes.first?.totalAmountCNY, 224)
        XCTAssertEqual(result.value.first?.quotes.first?.bookingURL?.absoluteString, "https://example.com/hotel/81001")
    }
}

private final class RollingGoURLProtocol: URLProtocol, @unchecked Sendable {
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

    nonisolated static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else {
            throw XCTSkip("URLSession request did not expose its encoded body")
        }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}
