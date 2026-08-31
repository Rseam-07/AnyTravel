import Foundation

struct PricingBackendClient {
    static let serviceURLDefaultsKey = "AnyTravelPricingServiceURL"

    func enrichAccommodationQuotes(
        _ accommodations: [AccommodationOption],
        destination: String,
        logistics: TripLogistics
    ) async -> [AccommodationOption] {
        guard let baseURL = configuredBaseURL(),
              let startDate = logistics.startDate,
              let endDate = logistics.endDate,
              !accommodations.isEmpty else {
            return accommodations
        }

        let endpoint = baseURL.appendingPathComponent("v1/quotes/accommodations")
        let requestBody = AccommodationQuoteRequest(
            destination: destination,
            checkIn: Self.dayFormatter.string(from: startDate),
            checkOut: Self.dayFormatter.string(from: endDate),
            adults: max(logistics.travelers, 1),
            rooms: max((logistics.travelers + 1) / 2, 1),
            hotels: accommodations.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            }
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 25
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return accommodations
            }
            let payload = try JSONDecoder.anyTravelPricing.decode(AccommodationQuoteResponse.self, from: data)
            return merge(payload.quotes, into: accommodations)
        } catch {
            return accommodations
        }
    }

    func enrichTransportOptions(
        _ currentOptions: [TransportOption],
        origin: String,
        destination: String,
        logistics: TripLogistics,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?
    ) async -> [TransportOption] {
        guard let baseURL = configuredBaseURL(),
              let departureDate = logistics.startDate,
              !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return currentOptions
        }

        let endpoint = baseURL.appendingPathComponent("v1/quotes/transport")
        let requestBody = TransportQuoteRequest(
            origin: origin,
            destination: destination,
            departureDate: Self.dayFormatter.string(from: departureDate),
            returnDate: logistics.endDate.map { Self.dayFormatter.string(from: $0) },
            adults: max(logistics.travelers, 1),
            modes: ["train", "flight"]
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 35
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return currentOptions
            }
            let payload = try JSONDecoder.anyTravelPricing.decode(TransportQuoteResponse.self, from: data)
            var liveOptions = payload.options.compactMap { backendOption in
                let mode = LongDistanceMode(rawValue: backendOption.mode)
                let fallbackAccessPoint = mode.flatMap { liveMode in
                    currentOptions.first(where: { $0.mode == liveMode })?.arrivalAccessPoint
                }
                return makeTransportOption(
                    from: backendOption,
                    accessPoints: accessPoints,
                    accommodation: accommodation,
                    fallbackAccessPoint: fallbackAccessPoint
                )
            }
            guard !liveOptions.isEmpty else { return currentOptions }
            let recommendedMode = logistics.preferredLongDistanceMode
            for index in liveOptions.indices {
                liveOptions[index].isRecommended = index == liveOptions.startIndex
                    && (recommendedMode == nil || recommendedMode == liveOptions[index].mode)
            }
            let liveModes = Set(liveOptions.map(\.mode))
            return (liveOptions + currentOptions.filter { !liveModes.contains($0.mode) })
                .sorted { lhs, rhs in
                    if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
                    return (lhs.durationMinutes ?? .max) < (rhs.durationMinutes ?? .max)
                }
        } catch {
            return currentOptions
        }
    }

    func healthCheck(urlText: String) async -> Bool {
        guard let baseURL = Self.normalizedURL(urlText),
              let healthURL = URL(string: "health", relativeTo: baseURL)?.absoluteURL else {
            return false
        }
        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 6
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private func configuredBaseURL() -> URL? {
        let value = UserDefaults.standard.string(forKey: Self.serviceURLDefaultsKey) ?? ""
        return Self.normalizedURL(value)
    }

    private static func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    private func merge(
        _ backendQuotes: [BackendAccommodationQuote],
        into accommodations: [AccommodationOption]
    ) -> [AccommodationOption] {
        accommodations.map { option in
            let matching = backendQuotes.filter { quote in
                if let hotelID = quote.hotelID, hotelID == option.id { return true }
                return Self.normalizedName(quote.hotelName) == Self.normalizedName(option.name)
                    || Self.normalizedName(quote.hotelName).contains(Self.normalizedName(option.name))
                    || Self.normalizedName(option.name).contains(Self.normalizedName(quote.hotelName))
            }
            guard !matching.isEmpty else { return option }

            var updated = option
            let liveQuotes = matching.compactMap { quote -> ProviderQuote? in
                guard let provider = TravelProvider(backendName: quote.provider), quote.amountCNY > 0 else {
                    return nil
                }
                return ProviderQuote(
                    provider: provider,
                    amountCNY: quote.amountCNY,
                    unit: quote.unit == "total" ? .total : .perNight,
                    kind: quote.kind == "indicative" ? .indicative : .live,
                    capturedAt: quote.capturedAt,
                    bookingURL: quote.bookingURL,
                    note: quote.note
                )
            }
            let liveProviders = Set(liveQuotes.map(\.provider))
            updated.quotes.removeAll { liveProviders.contains($0.provider) }
            updated.quotes.insert(contentsOf: liveQuotes, at: 0)
            return updated
        }
    }

    private func makeTransportOption(
        from option: BackendTransportOption,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?,
        fallbackAccessPoint: AccessPoint?
    ) -> TransportOption? {
        guard let provider = TravelProvider(backendName: option.provider),
              let mode = LongDistanceMode(rawValue: option.mode) else { return nil }
        let bestNamedPoint = accessPoints
            .filter { $0.kind == (mode == .flight ? .airport : .rail) }
            .min { lhs, rhs in
                Self.stationNameScore(lhs.name, target: option.destinationName)
                    < Self.stationNameScore(rhs.name, target: option.destinationName)
            }
        let arrivalPoint: AccessPoint?
        if let bestNamedPoint,
           Self.stationNameScore(bestNamedPoint.name, target: option.destinationName) < 10 {
            arrivalPoint = bestNamedPoint
        } else {
            arrivalPoint = fallbackAccessPoint
        }
        let transferMeters = arrivalPoint.flatMap { point in
            accommodation.map {
                LogisticsSearchService.distance(from: point.coordinate, to: $0.coordinate)
            }
        }
        let kind: QuoteKind = option.amountCNY == nil ? .checkOnProvider : .live
        let quote = ProviderQuote(
            provider: provider,
            amountCNY: option.amountCNY,
            unit: .perPerson,
            kind: kind,
            capturedAt: option.capturedAt,
            bookingURL: option.bookingURL,
            note: "\(option.fareName) · \(option.note)"
        )
        var reasons = ["\(Self.clockText(option.departureTime))–\(Self.clockText(option.arrivalTime)) · \(option.availability)"]
        if let transferMeters, let arrivalPoint {
            reasons.append("\(arrivalPoint.name)到住宿约\(transferMeters.anyTravelDistanceText)")
        }
        return TransportOption(
            mode: mode,
            title: "\(option.serviceNumber) · \(option.originName)→\(option.destinationName)",
            originName: option.originName,
            destinationName: option.destinationName,
            durationMinutes: option.durationMinutes,
            departureTime: option.departureTime,
            arrivalTime: option.arrivalTime,
            arrivalAccessPoint: arrivalPoint,
            hotelTransferMeters: transferMeters,
            quotes: [quote],
            recommendationReasons: reasons,
            isRecommended: false
        )
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "酒店", with: "")
            .replacingOccurrences(of: "宾馆", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func stationNameScore(_ value: String, target: String) -> Int {
        let name = normalizedStationName(value)
        let target = normalizedStationName(target)
        if name == target { return 0 }
        if name.contains(target) || target.contains(name) { return 1 }
        return 10
    }

    private static func normalizedStationName(_ value: String) -> String {
        value.replacingOccurrences(of: "站", with: "").replacingOccurrences(of: " ", with: "")
    }

    private static func clockText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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

private struct AccommodationQuoteRequest: Codable {
    struct Hotel: Codable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
    }

    let destination: String
    let checkIn: String
    let checkOut: String
    let adults: Int
    let rooms: Int
    let hotels: [Hotel]
}

private struct AccommodationQuoteResponse: Codable {
    var quotes: [BackendAccommodationQuote]
}

private struct TransportQuoteRequest: Codable {
    var origin: String
    var destination: String
    var departureDate: String
    var returnDate: String?
    var adults: Int
    var modes: [String]
}

private struct TransportQuoteResponse: Codable {
    var options: [BackendTransportOption]
}

private struct BackendTransportOption: Codable {
    var provider: String
    var mode: String
    var serviceNumber: String
    var originName: String
    var destinationName: String
    var departureTime: Date
    var arrivalTime: Date
    var durationMinutes: Int
    var amountCNY: Int?
    var fareName: String
    var availability: String
    var bookingURL: URL?
    var capturedAt: Date
    var note: String
}

private struct BackendAccommodationQuote: Codable {
    var hotelID: UUID?
    var hotelName: String
    var provider: String
    var amountCNY: Int
    var unit: String
    var kind: String
    var capturedAt: Date
    var bookingURL: URL?
    var note: String
}

private extension JSONDecoder {
    static let anyTravelPricing: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension TravelProvider {
    init?(backendName: String) {
        switch backendName.lowercased() {
        case "ctrip", "携程": self = .ctrip
        case "qunar", "去哪儿": self = .qunar
        case "trip.com", "tripcom": self = .tripCom
        case "skyscanner": self = .skyscanner
        case "rollinggo", "dida": self = .rollingGo
        case "12306", "railway12306": self = .railway12306
        case "official", "propertyofficial": self = .propertyOfficial
        default: return nil
        }
    }
}
