import Foundation

struct PricingEnrichmentResult<Value: Sendable>: Sendable {
    var value: Value
    var receivedCount: Int
    var capturedAt: Date
    var isCached: Bool
    var issues: [PricingProviderIssue]
}

struct PricingProviderIssue: Hashable, Sendable {
    var provider: String
    var status: String
    var detail: String?

    var message: String {
        let name = providerDisplayName
        switch status {
        case "disabled": return "\(name)尚未在报价节点启用"
        case "login_required": return "\(name)需要在报价节点重新登录"
        case "verification_required": return "\(name)需要在报价节点完成一次人工验证"
        case "dependency_missing": return "\(name)的采集组件尚未安装"
        case "browser_unavailable": return "\(name)的浏览器采集环境暂时不可用"
        case "city_id_missing": return "\(name)暂时无法识别这座城市"
        case "no_matching_quotes": return "\(name)已查询，但没有与当前地点名称可靠匹配的价格"
        case "no_visible_cards": return "\(name)页面已打开，但暂时没有可读取的酒店卡片"
        case "station_not_found": return "\(name)暂时无法识别出发地或到达地"
        case "failed":
            let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "\(name)本次没有返回结果" : "\(name)：\(trimmed)"
        default:
            let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "\(name)本次没有返回结果" : trimmed
        }
    }

    private var providerDisplayName: String {
        switch provider.lowercased() {
        case "rollinggo": "道旅 RollingGo"
        case "ctrip": "携程"
        case "qunar": "去哪儿"
        case "tongcheng", "ly": "同程旅行"
        case "trip.com", "tripcom": "Trip.com"
        case "12306", "railway12306": "铁路 12306"
        case "unknown": "报价渠道"
        default: provider
        }
    }
}

enum PricingBackendError: LocalizedError, Equatable {
    case serviceNotConfigured
    case missingDates
    case invalidResponse
    case httpFailure(statusCode: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured:
            "还没有连接报价节点。"
        case .missingDates:
            "先添上出发与返程日期，才能查询当天价格。"
        case .invalidResponse:
            "报价节点返回了无法识别的数据。"
        case let .httpFailure(statusCode, message):
            if let message, !message.isEmpty {
                "报价节点暂时拒绝了请求（\(statusCode)：\(message)）。"
            } else {
                "报价节点暂时拒绝了请求（\(statusCode)）。"
            }
        case let .network(message):
            "暂时没有接上报价节点：\(message)"
        }
    }
}

struct PricingBackendClient {
    static let serviceURLDefaultsKey = "AnyTravelPricingServiceURL"

    private let session: URLSession
    private let defaults: UserDefaults

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    var isConfigured: Bool { configuredBaseURL() != nil }

    func enrichAccommodationQuotes(
        _ accommodations: [AccommodationOption],
        destination: String,
        logistics: TripLogistics
    ) async throws -> PricingEnrichmentResult<[AccommodationOption]> {
        guard let baseURL = configuredBaseURL() else { throw PricingBackendError.serviceNotConfigured }
        guard let startDate = logistics.startDate, let endDate = logistics.endDate else {
            throw PricingBackendError.missingDates
        }
        guard !accommodations.isEmpty else {
            return PricingEnrichmentResult(
                value: accommodations,
                receivedCount: 0,
                capturedAt: .now,
                isCached: false,
                issues: []
            )
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
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw Self.httpError(response: response, data: data)
            }
            let payload = try JSONDecoder.anyTravelPricing.decode(AccommodationQuoteResponse.self, from: data)
            let recognizedCount = payload.quotes.filter {
                TravelProvider(backendName: $0.provider) != nil && $0.amountCNY > 0
            }.count
            return PricingEnrichmentResult(
                value: merge(payload.quotes, into: accommodations),
                receivedCount: recognizedCount,
                capturedAt: payload.capturedAt,
                isCached: payload.cached,
                issues: payload.diagnostics.compactMap(\.providerIssue)
            )
        } catch let error as PricingBackendError {
            throw error
        } catch is DecodingError {
            throw PricingBackendError.invalidResponse
        } catch {
            throw PricingBackendError.network(error.localizedDescription)
        }
    }

    func enrichTransportOptions(
        _ currentOptions: [TransportOption],
        origin: String,
        destination: String,
        logistics: TripLogistics,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?
    ) async throws -> PricingEnrichmentResult<[TransportOption]> {
        guard let baseURL = configuredBaseURL() else { throw PricingBackendError.serviceNotConfigured }
        guard let departureDate = logistics.startDate else { throw PricingBackendError.missingDates }
        guard !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PricingEnrichmentResult(
                value: currentOptions,
                receivedCount: 0,
                capturedAt: .now,
                isCached: false,
                issues: []
            )
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
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw Self.httpError(response: response, data: data)
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
            guard !liveOptions.isEmpty else {
                return PricingEnrichmentResult(
                    value: currentOptions,
                    receivedCount: 0,
                    capturedAt: payload.capturedAt,
                    isCached: payload.cached,
                    issues: payload.diagnostics.compactMap(\.providerIssue)
                )
            }
            let recommendedMode = logistics.preferredLongDistanceMode
            var recommendedDirections: Set<TransportDirection> = []
            for index in liveOptions.indices {
                let direction = liveOptions[index].journeyDirection
                let matchesPreference = recommendedMode == nil || recommendedMode == liveOptions[index].mode
                liveOptions[index].isRecommended = matchesPreference && !recommendedDirections.contains(direction)
                if liveOptions[index].isRecommended { recommendedDirections.insert(direction) }
            }
            let liveJourneyModes = Set(liveOptions.map {
                "\($0.journeyDirection.rawValue):\($0.mode.rawValue)"
            })
            let merged = (liveOptions + currentOptions.filter {
                !liveJourneyModes.contains("\($0.journeyDirection.rawValue):\($0.mode.rawValue)")
            })
                .sorted { lhs, rhs in
                    if lhs.journeyDirection != rhs.journeyDirection {
                        return lhs.journeyDirection == .outbound
                    }
                    if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
                    return (lhs.durationMinutes ?? .max) < (rhs.durationMinutes ?? .max)
                }
            return PricingEnrichmentResult(
                value: merged,
                receivedCount: liveOptions.count,
                capturedAt: payload.capturedAt,
                isCached: payload.cached,
                issues: payload.diagnostics.compactMap(\.providerIssue)
            )
        } catch let error as PricingBackendError {
            throw error
        } catch is DecodingError {
            throw PricingBackendError.invalidResponse
        } catch {
            throw PricingBackendError.network(error.localizedDescription)
        }
    }

    func enrichTicketQuotes(
        _ days: [ItineraryDay],
        destination: String,
        visitDate: Date?
    ) async throws -> PricingEnrichmentResult<[ItineraryDay]> {
        guard let baseURL = configuredBaseURL() else { throw PricingBackendError.serviceNotConfigured }
        let attractions = days.flatMap(\.stops).filter { $0.interest != .food }
        guard !attractions.isEmpty else {
            return PricingEnrichmentResult(
                value: days,
                receivedCount: 0,
                capturedAt: .now,
                isCached: false,
                issues: []
            )
        }

        let endpoint = baseURL.appendingPathComponent("v1/quotes/tickets")
        let requestBody = TicketQuoteRequest(
            destination: destination,
            visitDate: visitDate.map(Self.dayFormatter.string(from:)),
            attractions: attractions.map {
                .init(id: $0.id, name: $0.name, address: $0.address)
            }
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 25
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw Self.httpError(response: response, data: data)
            }
            let payload = try JSONDecoder.anyTravelPricing.decode(TicketQuoteResponse.self, from: data)
            let recognizedCount = payload.quotes.filter {
                TravelProvider(backendName: $0.provider) != nil && $0.amountCNY >= 0
            }.count
            let completedLookup = payload.diagnostics.contains {
                $0.status == "ok" || $0.status == "no_matching_quotes"
            }
            return PricingEnrichmentResult(
                value: merge(payload.quotes, into: days, clearUnmatched: completedLookup),
                receivedCount: recognizedCount,
                capturedAt: payload.capturedAt,
                isCached: payload.cached,
                issues: payload.diagnostics.compactMap(\.providerIssue)
            )
        } catch let error as PricingBackendError {
            throw error
        } catch is DecodingError {
            throw PricingBackendError.invalidResponse
        } catch {
            throw PricingBackendError.network(error.localizedDescription)
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
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private func configuredBaseURL() -> URL? {
        let value = defaults.string(forKey: Self.serviceURLDefaultsKey) ?? ""
        return Self.normalizedURL(value)
    }

    private static func httpError(response: URLResponse, data: Data) -> PricingBackendError {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let message = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data))?.error
        return .httpFailure(statusCode: statusCode, message: message)
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

    private func merge(
        _ backendQuotes: [BackendTicketQuote],
        into days: [ItineraryDay],
        clearUnmatched: Bool
    ) -> [ItineraryDay] {
        let quotesByID = Dictionary(uniqueKeysWithValues: backendQuotes.map { ($0.attractionID, $0) })
        return days.map { day in
            var updatedDay = day
            updatedDay.stops = day.stops.map { place in
                let quote = quotesByID[place.id] ?? backendQuotes.first {
                    Self.normalizedName($0.attractionName) == Self.normalizedName(place.name)
                }
                guard let quote else {
                    guard clearUnmatched, place.ticketQuote?.provider == .qunar else { return place }
                    var updatedPlace = place
                    updatedPlace.ticketQuote = nil
                    return updatedPlace
                }
                guard let provider = TravelProvider(backendName: quote.provider),
                      quote.amountCNY >= 0 else { return place }
                var updatedPlace = place
                updatedPlace.ticketQuote = ProviderQuote(
                    provider: provider,
                    amountCNY: quote.amountCNY,
                    unit: quote.unit == "total" ? .total : .perPerson,
                    kind: quote.kind == "indicative" ? .indicative : .live,
                    capturedAt: quote.capturedAt,
                    bookingURL: quote.bookingURL,
                    note: quote.note,
                    displayPriceText: quote.displayPriceText
                )
                return updatedPlace
            }
            return updatedDay
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
        let direction = option.direction.flatMap(TransportDirection.init(rawValue:)) ?? .outbound
        let localStationName = direction == .returnTrip ? option.originName : option.destinationName
        let bestNamedPoint = accessPoints
            .filter { $0.kind == (mode == .flight ? .airport : .rail) }
            .min { lhs, rhs in
                Self.stationNameScore(lhs.name, target: localStationName)
                    < Self.stationNameScore(rhs.name, target: localStationName)
            }
        let arrivalPoint: AccessPoint?
        if let bestNamedPoint,
           Self.stationNameScore(bestNamedPoint.name, target: localStationName) < 10 {
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
            let transferText = direction == .returnTrip
                ? "住宿到\(arrivalPoint.name)约\(transferMeters.anyTravelDistanceText)"
                : "\(arrivalPoint.name)到住宿约\(transferMeters.anyTravelDistanceText)"
            reasons.append(transferText)
        }
        return TransportOption(
            mode: mode,
            title: "\(option.serviceNumber) · \(option.originName)→\(option.destinationName)",
            originName: option.originName,
            destinationName: option.destinationName,
            direction: direction,
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
    var diagnostics: [BackendDiagnostic]
    var capturedAt: Date
    var cached: Bool
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
    var diagnostics: [BackendDiagnostic]
    var capturedAt: Date
    var cached: Bool
}

private struct TicketQuoteRequest: Codable {
    struct Attraction: Codable {
        var id: UUID
        var name: String
        var address: String
    }

    var destination: String
    var visitDate: String?
    var attractions: [Attraction]
}

private struct TicketQuoteResponse: Codable {
    var quotes: [BackendTicketQuote]
    var diagnostics: [BackendDiagnostic]
    var capturedAt: Date
    var cached: Bool
}

private struct BackendDiagnostic: Codable {
    var provider: String
    var status: String
    var detail: String?

    var providerIssue: PricingProviderIssue? {
        guard status != "ok" else { return nil }
        return PricingProviderIssue(provider: provider, status: status, detail: detail)
    }
}

private struct BackendErrorResponse: Codable {
    var error: String
}

private struct BackendTransportOption: Codable {
    var provider: String
    var mode: String
    var direction: String?
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

private struct BackendTicketQuote: Codable {
    var attractionID: UUID
    var attractionName: String
    var provider: String
    var amountCNY: Int
    var unit: String
    var kind: String
    var capturedAt: Date
    var bookingURL: URL?
    var note: String
    var displayPriceText: String?
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
        case "tongcheng", "ly", "同程旅行": self = .tongcheng
        case "trip.com", "tripcom": self = .tripCom
        case "skyscanner": self = .skyscanner
        case "rollinggo", "dida": self = .rollingGo
        case "12306", "railway12306": self = .railway12306
        case "official", "propertyofficial": self = .propertyOfficial
        default: return nil
        }
    }
}
