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
    private struct QueryOutcome {
        var hotels: [RollingGoHotel]
        var issue: PricingProviderIssue?
    }

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
        let adultsPerRoom = min(max(Int(ceil(Double(logistics.effectiveAdults) / Double(logistics.effectiveRooms))), 1), 8)
        let requestedSize = min(max(size, 1), 20)
        let locations = [destination] + anchors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != destination }
            .prefix(2)
        let capturedAt = Date.now

        let arguments = locations.enumerated().map { index, place in
            RollingGoSearchArguments(
                originQuery: "查找\(destination)\(index == 0 ? "" : "靠近\(place)")适合\(logistics.effectiveTotalTravelers)人入住的酒店和民宿，比较\(stayNights)晚实时价格",
                place: place,
                placeType: index == 0 ? "城市" : "景点",
                checkInParam: .init(
                    adultCount: adultsPerRoom,
                    childrenAges: logistics.effectiveChildrenAges,
                    rooms: logistics.effectiveRooms,
                    checkInDate: Self.dayFormatter.string(from: checkIn),
                    stayNights: stayNights
                ),
                size: index == 0 ? requestedSize : min(requestedSize, 10)
            )
        }
        let requestID = Int(capturedAt.timeIntervalSince1970)
        // The city and attraction searches are independent. Running them together
        // keeps a slow attraction query from delaying the first useful hotel cards.
        async let cityOutcome = searchOutcome(
            apiKey: key,
            arguments: arguments.first,
            requestID: requestID
        )
        async let firstAnchorOutcome = searchOutcome(
            apiKey: key,
            arguments: arguments.count > 1 ? arguments[1] : nil,
            requestID: requestID + 1
        )
        async let secondAnchorOutcome = searchOutcome(
            apiKey: key,
            arguments: arguments.count > 2 ? arguments[2] : nil,
            requestID: requestID + 2
        )
        let outcomes = await [cityOutcome, firstAnchorOutcome, secondAnchorOutcome]
        let entries = outcomes.flatMap(\.hotels).compactMap {
            Self.catalogEntry(from: $0, stayNights: stayNights, capturedAt: capturedAt)
        }
        var issues = outcomes.compactMap(\.issue)

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

    private func searchOutcome(
        apiKey: String,
        arguments: RollingGoSearchArguments?,
        requestID: Int
    ) async -> QueryOutcome {
        guard let arguments else { return QueryOutcome(hotels: [], issue: nil) }
        do {
            return QueryOutcome(
                hotels: try await callSearch(apiKey: apiKey, arguments: arguments, requestID: requestID),
                issue: nil
            )
        } catch {
            return QueryOutcome(
                hotels: [],
                issue: PricingProviderIssue(
                    provider: "rollinggo",
                    status: "failed",
                    detail: error.localizedDescription
                )
            )
        }
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
            hotels.append(contentsOf: Self.hotels(from: item.text))
        }
        return hotels
    }

    private static func hotels(from text: String) -> [RollingGoHotel] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var dictionaries: [[String: Any]] = []
        collectHotelDictionaries(root, into: &dictionaries)
        return dictionaries.compactMap(RollingGoHotel.init(dictionary:))
    }

    private static func collectHotelDictionaries(_ value: Any, into output: inout [[String: Any]]) {
        if let values = value as? [Any] {
            values.forEach { collectHotelDictionaries($0, into: &output) }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }
        let name = firstValue(in: dictionary, keys: ["name", "hotelName", "nameCn", "hotel_name"])
        let hasPrice = firstValue(
            in: dictionary,
            keys: ["displayPrice", "minPrice", "price", "lowestPrice", "totalPrice"]
        ) != nil
        let hasLatitude = firstValue(
            in: dictionary,
            keys: ["latitude", "lat", "hotelLat", "hotelLatitude"]
        ) != nil
        let hasLongitude = firstValue(
            in: dictionary,
            keys: ["longitude", "lng", "lon", "hotelLng", "hotelLongitude"]
        ) != nil
        let hasMetadata = firstValue(
            in: dictionary,
            keys: ["address", "hotelAddress", "brand", "starRating", "amenities", "hotelAmenities"]
        ) != nil
        if name != nil, hasPrice || (hasLatitude && hasLongitude) || hasMetadata {
            output.append(dictionary)
        }
        dictionary.values.forEach { collectHotelDictionaries($0, into: &output) }
    }

    private static func firstValue(in dictionary: [String: Any], keys: [String]) -> Any? {
        keys.lazy.compactMap { dictionary[$0] }.first
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
            providerHotelID: hotel.hotelID ?? "rollinggo-\(name)",
            providerHotelIDs: hotel.hotelID.map { ["rollinggo": $0] } ?? [:],
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
            if let index = output.firstIndex(where: { current in
                guard let currentCoordinate = current.coordinate,
                      let entryCoordinate = entry.coordinate else {
                    return AccommodationIdentity.normalizedName(current.name)
                        == AccommodationIdentity.normalizedName(entry.name)
                }
                return AccommodationIdentity.isSameProperty(
                    name: current.name,
                    coordinate: currentCoordinate,
                    brand: current.brand,
                    and: entry.name,
                    coordinate: entryCoordinate,
                    brand: entry.brand
                )
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
        var childrenAges: [Int] = []
        var rooms: Int = 1
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

private struct RollingGoHotel {
    var hotelID: String?
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

    init?(dictionary: [String: Any]) {
        name = Self.string(Self.first(dictionary, ["name", "hotelName", "nameCn", "hotel_name"]))
        guard !name.isEmpty else { return nil }
        hotelID = Self.string(Self.first(dictionary, ["hotelId", "hotelID", "id", "hotel_id"]))
            .nilIfEmpty
        bookingURL = Self.url(Self.first(dictionary, ["bookingUrl", "bookingURL", "url"]))
        brand = Self.string(Self.first(dictionary, ["brand", "brandName", "hotelBrand"])).nilIfEmpty
        address = Self.string(Self.first(dictionary, ["address", "hotelAddress", "addressCn"])).nilIfEmpty
        latitude = Self.number(Self.first(dictionary, ["latitude", "lat", "hotelLat", "hotelLatitude"]))
        longitude = Self.number(Self.first(dictionary, ["longitude", "lng", "lon", "hotelLng", "hotelLongitude"]))
        starRating = Self.number(Self.first(dictionary, ["starRating", "star", "starLevel"]))
        description = Self.string(Self.first(dictionary, ["description", "summary", "introduction"])).nilIfEmpty
        imageURL = Self.url(Self.first(dictionary, ["imageUrl", "imageURL", "coverImage", "cover"]))
        hotelAmenities = Self.strings(Self.first(dictionary, ["hotelAmenities", "amenities", "facilities", "facilityList", "services"]))
        tags = Self.strings(Self.first(dictionary, ["tags", "labels", "themes"]))

        if let structured = dictionary["price"] as? [String: Any] {
            price = RollingGoPrice(
                message: Self.string(structured["message"]).nilIfEmpty,
                hasPrice: Self.bool(structured["hasPrice"]),
                currency: Self.string(structured["currency"]).nilIfEmpty,
                lowestPrice: Self.number(Self.first(structured, ["lowestPrice", "totalPrice", "displayPrice", "minPrice", "price", "message"]))
            )
        } else {
            let amount = Self.number(Self.first(dictionary, ["displayPrice", "minPrice", "price", "lowestPrice", "totalPrice"]))
            price = amount.map { RollingGoPrice(message: nil, hasPrice: true, currency: "CNY", lowestPrice: $0) }
        }
    }

    private static func first(_ dictionary: [String: Any], _ keys: [String]) -> Any? {
        keys.lazy.compactMap { dictionary[$0] }.first
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        let raw = string(value)
        if let direct = Double(raw) { return direct }
        guard let match = raw.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(raw[match])
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        let raw = string(value).lowercased()
        if ["true", "1", "yes"].contains(raw) { return true }
        if ["false", "0", "no"].contains(raw) { return false }
        return nil
    }

    private static func url(_ value: Any?) -> URL? {
        let raw = string(value)
        return raw.isEmpty ? nil : URL(string: raw)
    }

    private static func strings(_ value: Any?) -> [String]? {
        guard let items = value as? [Any] else { return nil }
        let values = items.compactMap { item -> String? in
            if let dictionary = item as? [String: Any] {
                return string(first(dictionary, ["name", "title", "label"])).nilIfEmpty
            }
            return string(item).nilIfEmpty
        }
        return values.isEmpty ? nil : values
    }
}

private struct RollingGoPrice {
    var message: String?
    var hasPrice: Bool?
    var currency: String?
    var lowestPrice: Double?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
