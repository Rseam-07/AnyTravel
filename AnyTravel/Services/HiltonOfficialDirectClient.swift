import Foundation

enum HiltonOfficialDirectError: LocalizedError, Equatable {
    case missingDates
    case invalidResponse
    case httpFailure(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingDates: "先添上入住和离店日期，才能查询品牌官网。"
        case .invalidResponse: "希尔顿官网返回了无法识别的数据。"
        case let .httpFailure(status): "希尔顿官网暂时拒绝了请求（\(status)）。"
        case let .network(message): "希尔顿官网暂时没有抵达：\(message)"
        }
    }
}

/// Reads the public hotel directory used by Hilton China. The site's `minPrice`
/// is deliberately presented as an indicative starting price because the
/// directory response does not prove that it belongs to the selected dates.
struct HiltonOfficialDirectClient {
    private let session: URLSession
    private let endpoint: URL
    private let now: () -> Date

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://console-lls.hilton.com.cn/cgi/api/app/hotel/zh-CN/search")!,
        now: @escaping () -> Date = { .now }
    ) {
        self.session = session
        self.endpoint = endpoint
        self.now = now
    }

    var isAvailable: Bool { true }

    func searchAccommodationCatalog(
        destination: String,
        logistics: TripLogistics,
        size: Int = 20
    ) async throws -> PricingEnrichmentResult<[AccommodationCatalogEntry]> {
        guard let checkIn = logistics.startDate, let requestedCheckOut = logistics.endDate else {
            throw HiltonOfficialDirectError.missingDates
        }
        let calendar = Calendar(identifier: .gregorian)
        let minimumCheckOut = calendar.date(byAdding: .day, value: 1, to: checkIn) ?? requestedCheckOut
        let checkOut = max(requestedCheckOut, minimumCheckOut)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw HiltonOfficialDirectError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "keywords", value: destination.trimmingCharacters(in: .whitespacesAndNewlines))]
        guard let url = components.url else { throw HiltonOfficialDirectError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(NetworkIdentity.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw HiltonOfficialDirectError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw HiltonOfficialDirectError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw HiltonOfficialDirectError.httpFailure(http.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["success"] as? Bool) != false,
              let rows = ((root["data"] as? [String: Any])?["hotels"] as? [[String: Any]])
                ?? (root["hotels"] as? [[String: Any]]) else {
            throw HiltonOfficialDirectError.invalidResponse
        }

        let capturedAt = now()
        var seen = Set<String>()
        let entries = rows.compactMap { hotel -> AccommodationCatalogEntry? in
            let name = Self.string(Self.first(in: hotel, keys: ["hotelName", "name"]))
            let code = Self.string(Self.first(in: hotel, keys: ["hotelCode", "id"]))
            guard name.count >= 2, !code.isEmpty, seen.insert(code).inserted else { return nil }
            let location = hotel["location"] as? [String: Any]
            let coordinateDictionary = (location?["coordinate"] as? [String: Any])
                ?? (hotel["coordinate"] as? [String: Any])
            let latitude = Self.number(Self.first(in: coordinateDictionary ?? [:], keys: ["latitude", "lat"]))
            let longitude = Self.number(Self.first(in: coordinateDictionary ?? [:], keys: ["longitude", "lng"]))
            let coordinate: Coordinate? = if let latitude, let longitude,
                                             (-90...90).contains(latitude), (-180...180).contains(longitude) {
                Coordinate(latitude: latitude, longitude: longitude)
            } else {
                nil
            }
            let amount = Self.number(hotel["minPrice"])
                .map { max(Int($0.rounded()), 1) }
            let bookingURL = Self.bookingURL(
                hotelCode: code,
                checkIn: checkIn,
                checkOut: checkOut,
                adults: logistics.effectiveAdults
            )
            let tags = Self.uniqueStrings(
                Self.strings(hotel["sellingPoints"])
                    + Self.strings(hotel["tags"], keys: ["tagName", "name", "title", "label"])
            )
            let quote = ProviderQuote(
                provider: .propertyOfficial,
                amountCNY: amount,
                unit: .perNight,
                kind: amount == nil ? .checkOnProvider : .indicative,
                capturedAt: capturedAt,
                bookingURL: bookingURL,
                note: amount == nil
                    ? "前往希尔顿官网查看所选日期房型"
                    : "希尔顿官网当前公开起价；购买页已带入行程日期，请在官网复核",
                sourceLabel: "希尔顿官网",
                availability: amount == nil ? nil : "官网公开起价"
            )
            return AccommodationCatalogEntry(
                providerHotelID: "hilton-\(code)",
                providerHotelIDs: ["hilton-official": code],
                providers: [.propertyOfficial],
                sources: ["hilton-official"],
                name: name,
                brand: Self.brandName(hotel["brandCode"]),
                address: Self.string(location?["address"] ?? hotel["address"]),
                coordinate: coordinate,
                starRating: nil,
                guestRating: nil,
                description: Self.string(hotel["hotelDesc"]).nilIfEmpty,
                imageURL: Self.url((hotel["masterCover"] as? [String: Any])?["url"]),
                amenities: Array(Self.strings(hotel["amenities"]).prefix(16)),
                tags: Array(tags.prefix(16)),
                quotes: [quote]
            )
        }
        let limited = Array(entries.prefix(min(max(size, 1), 30)))
        let issue = PricingProviderIssue(
            provider: "hilton-official",
            status: limited.isEmpty ? "no_visible_cards" : "ok",
            detail: limited.isEmpty ? nil : "官网公开起价标为参考价；购买链接已带入行程日期"
        )
        return PricingEnrichmentResult(
            value: limited,
            receivedCount: limited.reduce(0) { count, hotel in
                count + hotel.quotes.filter { $0.amountCNY != nil }.count
            },
            capturedAt: capturedAt,
            isCached: false,
            issues: [issue]
        )
    }

    private static func bookingURL(hotelCode: String, checkIn: Date, checkOut: Date, adults: Int) -> URL? {
        var components = URLComponents(string: "https://www.hilton.com/zh-hans/book/reservation/deeplink/")
        components?.queryItems = [
            URLQueryItem(name: "ctyhocn", value: hotelCode),
            URLQueryItem(name: "arrivalDate", value: dayFormatter.string(from: checkIn)),
            URLQueryItem(name: "departureDate", value: dayFormatter.string(from: checkOut)),
            URLQueryItem(name: "room1NumAdults", value: String(min(max(adults, 1), 8)))
        ]
        return components?.url
    }

    private static func first(in dictionary: [String: Any], keys: [String]) -> Any? {
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

    private static func strings(_ value: Any?, keys: [String] = ["name", "title", "label"]) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { item in
            if let dictionary = item as? [String: Any] {
                return string(first(in: dictionary, keys: keys)).nilIfEmpty
            }
            return string(item).nilIfEmpty
        }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func url(_ value: Any?) -> URL? {
        let raw = string(value)
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    private static func brandName(_ value: Any?) -> String {
        switch string(value).uppercased() {
        case "WA": "华尔道夫"
        case "CH": "康莱德"
        case "LX": "LXR"
        case "HI": "希尔顿"
        case "QQ": "嘉悦里"
        case "DT": "希尔顿逸林"
        case "UP": "格芮精选"
        case "PY": "启缤精选"
        case "ES": "希尔顿安泊"
        case "HT", "RU": "希尔顿欢朋"
        case "GI": "希尔顿花园"
        case "HW": "欣庭"
        case "UA": "希尔顿惠庭"
        default: "希尔顿集团"
        }
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
