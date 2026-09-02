import Foundation

struct AMapPlaceClient {
    private let session: URLSession
    private let defaults: UserDefaults
    private let directAPIKey: () -> String

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        directAPIKey: @escaping () -> String = { EmbeddedServiceConfiguration.amapWebServiceKey }
    ) {
        self.session = session
        self.defaults = defaults
        self.directAPIKey = directAPIKey
    }

    var isConfigured: Bool {
        configuredBaseURL() != nil || !directAPIKey().isEmpty
    }

    func search(
        keywords: String,
        city: String,
        interest: TripInterest,
        limit: Int = 12
    ) async throws -> [TravelPlace] {
        if let baseURL = configuredBaseURL() {
            do {
                return try await searchThroughCompanion(
                    baseURL: baseURL,
                    keywords: keywords,
                    city: city,
                    interest: interest,
                    limit: limit
                )
            } catch where !directAPIKey().isEmpty {
                return try await searchDirectly(
                    keywords: keywords,
                    city: city,
                    interest: interest,
                    limit: limit
                )
            }
        }
        return try await searchDirectly(keywords: keywords, city: city, interest: interest, limit: limit)
    }

    private func searchThroughCompanion(
        baseURL: URL,
        keywords: String,
        city: String,
        interest: TripInterest,
        limit: Int
    ) async throws -> [TravelPlace] {
        let endpoint = baseURL.appendingPathComponent("v1/places/search")
        let payload = AMapPlaceRequest(keywords: keywords, city: city, limit: min(max(limit, 1), 20))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw AMapPlaceClientError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AMapPlaceClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = try? JSONDecoder().decode(AMapBackendError.self, from: data)
            throw AMapPlaceClientError.httpFailure(
                statusCode: http.statusCode,
                message: detail?.message ?? detail?.error
            )
        }
        guard let decoded = try? JSONDecoder.anyTravelAMap.decode(AMapPlaceResponse.self, from: data),
              decoded.sourceCRS == "GCJ-02",
              decoded.outputCRS.hasPrefix("WGS84") else {
            throw AMapPlaceClientError.invalidResponse
        }
        return decoded.places.compactMap { place in
            guard !place.name.isEmpty,
                  (-90...90).contains(place.coordinate.latitude),
                  (-180...180).contains(place.coordinate.longitude) else { return nil }
            return TravelPlace(
                name: place.name,
                address: place.address,
                coordinate: place.coordinate,
                interest: interest,
                source: "高德地图 · Web服务",
                openingHoursToday: place.openingHoursToday,
                openingHoursWeek: place.openingHoursWeek,
                popularity: AttractionPopularity(
                    score: (place.rating ?? 0) * 12,
                    rating: place.rating,
                    evidence: [place.rating.map { "高德评分 \($0.formatted(.number.precision(.fractionLength(1))))" }].compactMap { $0 }
                )
            )
        }
    }

    private func searchDirectly(
        keywords: String,
        city: String,
        interest: TripInterest,
        limit: Int
    ) async throws -> [TravelPlace] {
        let key = directAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AMapPlaceClientError.serviceNotConfigured }
        var components = URLComponents(string: "https://restapi.amap.com/v5/place/text")!
        components.queryItems = [
            URLQueryItem(name: "keywords", value: keywords),
            URLQueryItem(name: "region", value: city),
            URLQueryItem(name: "city_limit", value: "true"),
            URLQueryItem(name: "page_size", value: String(min(max(limit, 1), 20))),
            URLQueryItem(name: "page_num", value: "1"),
            URLQueryItem(name: "show_fields", value: "business"),
            URLQueryItem(name: "key", value: key)
        ]
        guard let endpoint = components.url else { throw AMapPlaceClientError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 18
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw AMapPlaceClientError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AMapPlaceClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AMapPlaceClientError.httpFailure(statusCode: http.statusCode, message: nil)
        }
        guard let payload = try? JSONDecoder().decode(AMapDirectResponse.self, from: data) else {
            throw AMapPlaceClientError.invalidResponse
        }
        guard payload.status == "1" else {
            throw AMapPlaceClientError.httpFailure(
                statusCode: 422,
                message: payload.info ?? payload.infocode
            )
        }
        return payload.pois.enumerated().compactMap { index, poi in
            let parts = poi.location.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2, !poi.name.isEmpty else { return nil }
            let coordinate = Self.gcj02ToWGS84(longitude: parts[0], latitude: parts[1])
            let rating = poi.business?.rating?.value
            var evidence = ["高德在线结果第 \(index + 1) 位"]
            if let rating { evidence.append("评分 \(rating.formatted(.number.precision(.fractionLength(1))))") }
            return TravelPlace(
                name: poi.name,
                address: poi.normalizedAddress,
                coordinate: coordinate,
                interest: interest,
                source: "高德地图 · Web服务直连",
                openingHoursToday: poi.business?.openingHoursToday,
                openingHoursWeek: poi.business?.openingHoursWeek,
                popularity: AttractionPopularity(
                    score: max(70 - Double(index) * 2 + (rating ?? 0) * 12, 1),
                    rating: rating,
                    evidence: evidence
                )
            )
        }
    }

    private func configuredBaseURL() -> URL? {
        let value = defaults.string(forKey: PricingBackendClient.serviceURLDefaultsKey) ?? ""
        return TravelAssistantClient.normalizedBaseURL(value, allowLocalHTTP: true)
    }
}

enum AMapPlaceClientError: LocalizedError, Equatable {
    case serviceNotConfigured
    case invalidResponse
    case httpFailure(statusCode: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured: "AnyTravel 伴随服务尚未配置。"
        case .invalidResponse: "高德地点响应缺少坐标来源信息。"
        case let .httpFailure(statusCode, message): "高德地点服务暂不可用（\(statusCode)）\(message.map { "：\($0)" } ?? "")"
        case let .network(message): "高德地点服务暂时走散了：\(message)"
        }
    }
}

private struct AMapPlaceRequest: Encodable {
    var keywords: String
    var city: String
    var limit: Int
}

private struct AMapPlaceResponse: Decodable {
    struct Place: Decodable {
        var name: String
        var address: String
        var coordinate: Coordinate
        var openingHoursToday: String?
        var openingHoursWeek: String?
        var rating: Double?
        var averageCostCNY: Double?
    }

    var places: [Place]
    var source: String
    var sourceCRS: String
    var outputCRS: String
    var capturedAt: Date
}

private struct AMapDirectResponse: Decodable {
    struct POI: Decodable {
        struct Business: Decodable {
            var openingHoursToday: String?
            var openingHoursWeek: String?
            var rating: AMapFlexibleDouble?

            enum CodingKeys: String, CodingKey {
                case rating
                case openingHoursToday = "opentime_today"
                case openingHoursWeek = "opentime_week"
            }
        }

        var name: String
        var address: AMapFlexibleString
        var location: String
        var business: Business?

        var normalizedAddress: String {
            let result = address.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? "地址以高德详情为准" : result
        }
    }

    var status: String
    var info: String?
    var infocode: String?
    var pois: [POI]
}

private struct AMapFlexibleDouble: Decodable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { value = number }
        else if let text = try? container.decode(String.self) { value = Double(text) }
        else { value = nil }
    }
}

private struct AMapFlexibleString: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { value = text }
        else if let parts = try? container.decode([String].self) { value = parts.joined() }
        else { value = "" }
    }
}

private extension AMapPlaceClient {
    static func gcj02ToWGS84(longitude: Double, latitude: Double) -> Coordinate {
        guard !outsideChina(longitude: longitude, latitude: latitude) else {
            return Coordinate(latitude: latitude, longitude: longitude)
        }
        var estimateLongitude = longitude
        var estimateLatitude = latitude
        for _ in 0..<3 {
            let shifted = wgs84ToGCJ02(longitude: estimateLongitude, latitude: estimateLatitude)
            estimateLongitude -= shifted.longitude - longitude
            estimateLatitude -= shifted.latitude - latitude
        }
        return Coordinate(latitude: estimateLatitude, longitude: estimateLongitude)
    }

    static func wgs84ToGCJ02(longitude: Double, latitude: Double) -> (longitude: Double, latitude: Double) {
        guard !outsideChina(longitude: longitude, latitude: latitude) else { return (longitude, latitude) }
        let axis = 6_378_245.0
        let eccentricity = 0.00669342162296594323
        var latitudeDelta = transformLatitude(longitude - 105, latitude - 35)
        var longitudeDelta = transformLongitude(longitude - 105, latitude - 35)
        let radians = latitude / 180 * .pi
        var magic = sin(radians)
        magic = 1 - eccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        latitudeDelta = latitudeDelta * 180 / ((axis * (1 - eccentricity)) / (magic * sqrtMagic) * .pi)
        longitudeDelta = longitudeDelta * 180 / (axis / sqrtMagic * cos(radians) * .pi)
        return (longitude + longitudeDelta, latitude + latitudeDelta)
    }

    static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        result += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return result
    }

    static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        result += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return result
    }

    static func outsideChina(longitude: Double, latitude: Double) -> Bool {
        longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271
    }
}

private struct AMapBackendError: Decodable {
    var error: String?
    var message: String?
}

private extension JSONDecoder {
    static let anyTravelAMap: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }()
}
