import Foundation

enum RollingGoDirectError: LocalizedError, Equatable {
    case notConfigured
    case missingDates
    case invalidResponse
    case httpFailure(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "内置酒店价格源尚未配置。"
        case .missingDates: "先添上入住和离店日期，才能查询酒店价格。"
        case .invalidResponse: "酒店价格源返回了无法识别的数据。"
        case let .httpFailure(status): "酒店价格源暂时拒绝了请求（\(status)）。"
        case let .network(message): "酒店价格暂时没有抵达：\(message)"
        }
    }
}

struct RollingGoDirectClient {
    private let session: URLSession
    private let apiKey: () -> String
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        apiKey: @escaping () -> String = { EmbeddedServiceConfiguration.rollingGoAPIKey },
        endpoint: URL = URL(string: "https://mcp.rollinggo.cn/mcp")!
    ) {
        self.session = session
        self.apiKey = apiKey
        self.endpoint = endpoint
    }

    var isConfigured: Bool { !apiKey().isEmpty }

    func searchAccommodationCatalog(
        destination: String,
        logistics: TripLogistics,
        anchors: [String] = [],
        size: Int = 20
    ) async throws -> PricingEnrichmentResult<[AccommodationCatalogEntry]> {
        let key = apiKey()
        guard !key.isEmpty else { throw RollingGoDirectError.notConfigured }
        guard let checkIn = logistics.startDate, let requestedCheckOut = logistics.endDate else {
            throw RollingGoDirectError.missingDates
        }
        let calendar = Calendar(identifier: .gregorian)
        let minimumCheckOut = calendar.date(byAdding: .day, value: 1, to: checkIn) ?? requestedCheckOut
        let checkOut = max(requestedCheckOut, minimumCheckOut)
        let stayNights = max(calendar.dateComponents([.day], from: checkIn, to: checkOut).day ?? 1, 1)
        let adultsPerRoom = min(max(logistics.travelers / max((logistics.travelers + 1) / 2, 1), 1), 8)
        let requestedSize = min(max(size, 1), 20)
        let locations = [destination] + anchors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != destination }
            .prefix(2)
        let capturedAt = Date.now

        var entries: [AccommodationCatalogEntry] = []
        var issues: [PricingProviderIssue] = []
        for (index, place) in locations.enumerated() {
            do {
                let hotels = try await callSearch(
                    apiKey: key,
                    arguments: RollingGoSearchArguments(
                        originQuery: "查找\(destination)\(index == 0 ? "" : "靠近\(place)")适合\(logistics.travelers)人入住的酒店和民宿，比较\(stayNights)晚实时价格",
                        place: place,
                        placeType: index == 0 ? "城市" : "景点",
                        checkInParam: .init(
                            adultCount: adultsPerRoom,
                            checkInDate: Self.dayFormatter.string(from: checkIn),
                            stayNights: stayNights
                        ),
                        size: index == 0 ? requestedSize : min(requestedSize, 10)
                    ),
                    requestID: Int(capturedAt.timeIntervalSince1970) + index
                )
                entries.append(contentsOf: hotels.compactMap {
                    Self.catalogEntry(from: $0, stayNights: stayNights, capturedAt: capturedAt)
                })
            } catch {
                issues.append(
                    PricingProviderIssue(
                        provider: "rollinggo",
                        status: "failed",
                        detail: error.localizedDescription
                    )
                )
            }
        }

        let merged = Self.deduplicated(entries)
        if merged.isEmpty, issues.isEmpty {
            issues.append(.init(provider: "rollinggo", status: "no_matching_quotes", detail: nil))
        }
        return PricingEnrichmentResult(
            value: Array(merged.prefix(40)),
            receivedCount: merged.flatMap(\.quotes).filter { $0.amountCNY != nil }.count,
            capturedAt: capturedAt,
            isCached: false,
            issues: issues
        )
    }

    private func callSearch(
        apiKey: String,
        arguments: RollingGoSearchArguments,
        requestID: Int
    ) async throws -> [RollingGoHotel] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 28
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.httpBody = try JSONEncoder().encode(
            RollingGoMCPRequest(
                jsonrpc: "2.0",
                method: "tools/call",
                params: .init(name: "searchHotels", arguments: arguments),
                id: requestID
            )
        )

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw RollingGoDirectError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw RollingGoDirectError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RollingGoDirectError.httpFailure(http.statusCode)
        }
        let payloadData = try Self.payloadData(from: data)
        guard let outer = try? JSONDecoder().decode(RollingGoMCPResponse.self, from: payloadData),
              let content = outer.result?.content else { throw RollingGoDirectError.invalidResponse }
        var hotels: [RollingGoHotel] = []
        for item in content where item.type == "text" {
            guard let textData = item.text.data(using: .utf8),
                  let search = try? JSONDecoder().decode(RollingGoSearchResponse.self, from: textData) else { continue }
            hotels.append(contentsOf: search.hotelInformationList ?? [])
        }
        return hotels
    }

    private static func payloadData(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { throw RollingGoDirectError.invalidResponse }
        let lines = text.split(whereSeparator: \Character.isNewline)
        if let dataLine = lines.last(where: { $0.hasPrefix("data:") }) {
            let json = dataLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let result = json.data(using: .utf8) else { throw RollingGoDirectError.invalidResponse }
            return result
        }
        return data
    }

    private static func catalogEntry(
        from hotel: RollingGoHotel,
        stayNights: Int,
        capturedAt: Date
    ) -> AccommodationCatalogEntry? {
        let name = hotel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let latitude = hotel.latitude,
              let longitude = hotel.longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        let price = nightlyPrice(from: hotel.price, stayNights: stayNights)
        let quote = ProviderQuote(
            provider: .rollingGo,
            amountCNY: price,
            unit: .perNight,
            kind: price == nil ? .checkOnProvider : .live,
            capturedAt: capturedAt,
            bookingURL: hotel.bookingURL,
            note: price == nil
                ? "道旅已返回酒店资料，进入房型页查看当前价格"
                : "道旅实时展示价；选定房型后仍需锁价确认",
            sourceLabel: "道旅 RollingGo",
            totalAmountCNY: hotel.price?.lowestPrice.flatMap { Int($0.rounded()) }
        )
        return AccommodationCatalogEntry(
            providerHotelID: hotel.hotelID.map(String.init) ?? "rollinggo-\(name)",
            providerHotelIDs: hotel.hotelID.map { ["rollinggo": String($0)] } ?? [:],
            providers: [.rollingGo],
            sources: ["rollinggo"],
            name: name,
            brand: hotel.brand,
            address: hotel.address ?? "",
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            starRating: hotel.starRating,
            guestRating: nil,
            description: hotel.description.map(strippingHTML),
            imageURL: hotel.imageURL,
            amenities: Array((hotel.hotelAmenities ?? []).prefix(12)),
            tags: Array((hotel.tags ?? []).prefix(10)),
            quotes: [quote]
        )
    }

    private static func nightlyPrice(from price: RollingGoPrice?, stayNights: Int) -> Int? {
        guard let value = price?.lowestPrice, value > 0 else { return nil }
        let message = price?.message ?? ""
        let isStayTotal = message.contains("总价") || message.contains("合计")
        let amount = isStayTotal ? value / Double(max(stayNights, 1)) : value
        return max(Int(amount.rounded()), 1)
    }

    private static func deduplicated(_ entries: [AccommodationCatalogEntry]) -> [AccommodationCatalogEntry] {
        var output: [AccommodationCatalogEntry] = []
        for entry in entries {
            let key = entry.name
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
            if let index = output.firstIndex(where: {
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                    .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined() == key
            }) {
                if (entry.amountCNY ?? .max) < (output[index].amountCNY ?? .max) { output[index] = entry }
            } else {
                output.append(entry)
            }
        }
        return output.sorted { ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max) }
    }

    private static func strippingHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct RollingGoMCPRequest: Encodable {
    struct Parameters: Encodable {
        var name: String
        var arguments: RollingGoSearchArguments
    }
    var jsonrpc: String
    var method: String
    var params: Parameters
    var id: Int
}

private struct RollingGoSearchArguments: Encodable {
    struct CheckIn: Encodable {
        var adultCount: Int
        var checkInDate: String
        var stayNights: Int
    }
    var originQuery: String
    var place: String
    var placeType: String
    var checkInParam: CheckIn
    var size: Int
}

private struct RollingGoMCPResponse: Decodable {
    struct Result: Decodable {
        struct Content: Decodable {
            var type: String
            var text: String
        }
        var content: [Content]
    }
    var result: Result?
}

private struct RollingGoSearchResponse: Decodable {
    var hotelInformationList: [RollingGoHotel]?
}

private struct RollingGoHotel: Decodable {
    var hotelID: Int?
    var bookingURL: URL?
    var name: String
    var brand: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var starRating: Double?
    var price: RollingGoPrice?
    var description: String?
    var imageURL: URL?
    var hotelAmenities: [String]?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case hotelID = "hotelId"
        case bookingURL = "bookingUrl"
        case name, brand, address, latitude, longitude, starRating, price, description
        case imageURL = "imageUrl"
        case hotelAmenities, tags
    }
}

private struct RollingGoPrice: Decodable {
    var message: String?
    var hasPrice: Bool?
    var currency: String?
    var lowestPrice: Double?
}
