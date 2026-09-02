import XCTest
@testable import AnyTravel

final class Railway12306DirectClientTests: XCTestCase {
    override func tearDown() {
        RailwayURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testDirectSearchReturnsOutboundAndReturnPricesWithoutCompanionService() async throws {
        RailwayURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body: Data
            switch url.path {
            case "/station_name.js":
                body = Data("var station_names ='@shh|上海|SHH|shanghai|sh|20|0712|上海|||@szh|苏州|SZH|suzhou|sz|1215|0710|苏州|||';".utf8)
            case "/otn/leftTicket/init":
                body = Data("<html></html>".utf8)
            case "/otn/leftTicket/query":
                let from = RailwayURLProtocol.queryValue(named: "leftTicketDTO.from_station", in: url)
                let outbound = from == "SHH"
                let row = RailwayURLProtocol.trainRow(
                    trainNumber: outbound ? "55000G70010" : "55000G70280",
                    serviceNumber: outbound ? "G7001" : "G7028",
                    originCode: outbound ? "SHH" : "SZH",
                    destinationCode: outbound ? "SZH" : "SHH",
                    departure: outbound ? "09:00" : "18:00",
                    arrival: outbound ? "09:31" : "18:32"
                )
                body = try JSONSerialization.data(withJSONObject: [
                    "status": true,
                    "data": [
                        "map": ["SHH": "上海", "SZH": "苏州"],
                        "result": [row]
                    ]
                ])
            case "/otn/leftTicket/queryTicketPrice":
                let trainNumber = RailwayURLProtocol.queryValue(named: "train_no", in: url)
                let amount = trainNumber.contains("G7001") ? "¥39.5" : "¥42.0"
                body = try JSONSerialization.data(withJSONObject: ["status": true, "data": ["O": amount]])
            default:
                throw URLError(.unsupportedURL)
            }
            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": url.path.hasSuffix("query") || url.path.hasSuffix("queryTicketPrice") ? "application/json" : "text/plain"]
                )!,
                body
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RailwayURLProtocol.self]
        let client = Railway12306DirectClient(
            session: URLSession(configuration: configuration),
            stationURL: URL(string: "https://rail.example/station_name.js")!,
            baseURL: URL(string: "https://rail.example/otn")!,
            resultLimit: 4
        )
        var logistics = TripLogistics()
        logistics.startDate = Date(timeIntervalSince1970: 2_000_000_000)
        logistics.endDate = Date(timeIntervalSince1970: 2_000_086_400)
        let estimate = TransportOption(
            mode: .train,
            title: "高铁抵达苏州",
            originName: "上海",
            destinationName: "苏州"
        )
        let flight = TransportOption(
            mode: .flight,
            title: "飞机抵达苏州",
            originName: "上海",
            destinationName: "苏州"
        )
        let station = AccessPoint(
            name: "苏州站",
            coordinate: Coordinate(latitude: 31.329, longitude: 120.607),
            kind: .rail
        )

        let result = try await client.enrichTransportOptions(
            [estimate, flight],
            origin: "上海市",
            destination: "苏州市",
            logistics: logistics,
            accessPoints: [station],
            accommodation: nil
        )

        let outbound = try XCTUnwrap(result.value.first { $0.journeyDirection == .outbound && $0.mode == .train })
        let returnTrip = try XCTUnwrap(result.value.first { $0.journeyDirection == .returnTrip && $0.mode == .train })
        XCTAssertEqual(outbound.title, "G7001 · 上海→苏州")
        XCTAssertEqual(outbound.quotes.first?.amountCNY, 40)
        XCTAssertEqual(outbound.quotes.first?.kind, .live)
        XCTAssertEqual(outbound.quotes.first?.availability, "二等座有票 · 一等座有票")
        XCTAssertEqual(outbound.arrivalAccessPoint?.name, "苏州站")
        XCTAssertEqual(returnTrip.quotes.first?.amountCNY, 42)
        XCTAssertEqual(result.receivedCount, 2)
        XCTAssertTrue(result.value.contains { $0.id == flight.id })
        XCTAssertFalse(result.isCached)
    }
}

private final class RailwayURLProtocol: URLProtocol, @unchecked Sendable {
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

    nonisolated static func queryValue(named name: String, in url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == name })?.value ?? ""
    }

    nonisolated static func trainRow(
        trainNumber: String,
        serviceNumber: String,
        originCode: String,
        destinationCode: String,
        departure: String,
        arrival: String
    ) -> String {
        var fields = Array(repeating: "", count: 58)
        fields[2] = trainNumber
        fields[3] = serviceNumber
        fields[6] = originCode
        fields[7] = destinationCode
        fields[8] = departure
        fields[9] = arrival
        fields[10] = "00:32"
        fields[11] = "Y"
        fields[16] = "01"
        fields[17] = "02"
        fields[30] = "有"
        fields[31] = "有"
        fields[35] = "OMO"
        return fields.joined(separator: "|")
    }
}
