import Foundation

struct AMapPlaceClient {
    private let session: URLSession
    private let defaults: UserDefaults

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    var isConfigured: Bool {
        configuredBaseURL() != nil
    }

    func search(
        keywords: String,
        city: String,
        interest: TripInterest,
        limit: Int = 12
    ) async throws -> [TravelPlace] {
        guard let baseURL = configuredBaseURL() else { throw AMapPlaceClientError.serviceNotConfigured }
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
                openingHoursWeek: place.openingHoursWeek
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
    }

    var places: [Place]
    var source: String
    var sourceCRS: String
    var outputCRS: String
    var capturedAt: Date
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
