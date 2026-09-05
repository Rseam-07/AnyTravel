import Foundation

enum AccorOfficialDirectError: LocalizedError, Equatable {
    case missingDates
    case invalidResponse
    case httpFailure(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingDates: "先添上入住和离店日期，才能查询品牌官网。"
        case .invalidResponse: "雅高集团官网返回了无法识别的数据。"
        case let .httpFailure(status): "雅高集团官网暂时拒绝了请求（\(status)）。"
        case let .network(message): "雅高集团官网暂时没有抵达：\(message)"
        }
    }
}

/// Reads the same public hotel search and selected-date rate responses used by
/// all.accor.com. Results keep the stay total as well as the normalized nightly
/// amount, so the UI never has to guess what a number represents.
struct AccorOfficialDirectClient: @unchecked Sendable {
    private struct CatalogHotel: Sendable {
        var code: String
        var name: String
        var brand: String?
        var address: String
        var coordinate: Coordinate?
        var starRating: Double?
        var guestRating: Double?
        var description: String?
        var imageURL: URL?
        var amenities: [String]
        var tags: [String]
    }

    private struct Rate: Sendable {
        var totalAmountCNY: Int
        var roomName: String?
        var mealPlan: String?
        var cancellationPolicy: String?
    }

    private struct IndexedRate: Sendable {
        var index: Int
        var value: Rate?
    }

    private let session: URLSession
    private let now: @Sendable () -> Date
    private let algoliaApplicationID: String
    private let algoliaSearchKey: String
    private let bffAPIKey: String
    private let bffEndpoint: URL

    init(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now },
        algoliaApplicationID: String = "TEBW21BCFZ",
        algoliaSearchKey: String = "1a6f0c3b77791a299d98f6b981f2715d",
        bffAPIKey: String = "l7xx5b9f4a053aaf43d8bc05bcc266dd8532",
        bffEndpoint: URL = URL(string: "https://api.accor.com/bff/v1/graphql")!
    ) {
        self.session = session
        self.now = now
        self.algoliaApplicationID = algoliaApplicationID
        self.algoliaSearchKey = algoliaSearchKey
        self.bffAPIKey = bffAPIKey
        self.bffEndpoint = bffEndpoint
    }

    var isAvailable: Bool { true }

    func searchAccommodationCatalog(
        destination: String,
        logistics: TripLogistics,
        size: Int = 8
    ) async throws -> PricingEnrichmentResult<[AccommodationCatalogEntry]> {
        guard let requestedCheckIn = logistics.startDate, let requestedCheckOut = logistics.endDate else {
            throw AccorOfficialDirectError.missingDates
        }
        let calendar = Calendar(identifier: .gregorian)
        let checkIn = calendar.startOfDay(for: requestedCheckIn)
        let minimumCheckOut = calendar.date(byAdding: .day, value: 1, to: checkIn) ?? requestedCheckOut
        let checkOut = max(calendar.startOfDay(for: requestedCheckOut), minimumCheckOut)
        let nights = max(calendar.dateComponents([.day], from: checkIn, to: checkOut).day ?? 1, 1)
        let limit = min(max(size, 1), 10)
        let hotels = try await catalog(destination: destination, size: limit)

        let rates = await withTaskGroup(of: IndexedRate.self, returning: [Int: Rate].self) { group in
            for (index, hotel) in hotels.enumerated() {
                group.addTask {
                    let rate = try? await Self.fetchRate(
                        hotelCode: hotel.code,
                        checkIn: checkIn,
                        checkOut: checkOut,
                        adults: logistics.effectiveAdults,
                        childrenAges: logistics.effectiveChildrenAges,
                        session: session,
                        endpoint: bffEndpoint,
                        apiKey: bffAPIKey
                    )
                    return IndexedRate(index: index, value: rate)
                }
            }
            var result: [Int: Rate] = [:]
            for await item in group {
                if let value = item.value { result[item.index] = value }
            }
            return result
        }
        try Task.checkCancellation()

        let capturedAt = now()
        let entries = hotels.enumerated().map { index, hotel in
            let rate = rates[index]
            let nightlyAmount = rate.map { max(Int((Double($0.totalAmountCNY) / Double(nights)).rounded()), 1) }
            let bookingURL = Self.bookingURL(
                hotelCode: hotel.code,
                checkIn: checkIn,
                checkOut: checkOut,
                adults: logistics.effectiveAdults
            )
            let quote = ProviderQuote(
                provider: .propertyOfficial,
                amountCNY: nightlyAmount,
                unit: .perNight,
                kind: nightlyAmount == nil ? .checkOnProvider : .live,
                capturedAt: capturedAt,
                bookingURL: bookingURL,
                note: nightlyAmount == nil
                    ? "前往雅高集团官网查看所选日期房型"
                    : "雅高官网所选日期公开价\(rate?.mealPlan.map { " · \($0)" } ?? "")；结算前请复核税费与库存",
                displayPriceText: nightlyAmount.map { "¥\($0)起" },
                sourceLabel: "雅高集团官网",
                totalAmountCNY: rate?.totalAmountCNY,
                roomName: rate?.roomName,
                mealPlan: rate?.mealPlan,
                cancellationPolicy: rate?.cancellationPolicy,
                availability: nightlyAmount == nil ? nil : "所选日期有公开报价"
            )
            return AccommodationCatalogEntry(
                providerHotelID: "accor-\(hotel.code)",
                providerHotelIDs: ["accor-official": hotel.code],
                providers: [.propertyOfficial],
                sources: ["accor-official"],
                name: hotel.name,
                brand: hotel.brand,
                address: hotel.address,
                coordinate: hotel.coordinate,
                starRating: hotel.starRating,
                guestRating: hotel.guestRating,
                description: hotel.description,
                imageURL: hotel.imageURL,
                amenities: hotel.amenities,
                tags: hotel.tags,
                quotes: [quote]
            )
        }
        let pricedCount = entries.filter { $0.amountCNY != nil }.count
        return PricingEnrichmentResult(
            value: entries,
            receivedCount: pricedCount,
            capturedAt: capturedAt,
            isCached: false,
            issues: [PricingProviderIssue(
                provider: "accor-official",
                status: entries.isEmpty ? "no_visible_cards" : "ok",
                detail: pricedCount > 0
                    ? "雅高官网已按所选入住日期返回公开房价"
                    : "雅高官网已返回酒店目录；当前日期未见可售报价"
            )]
        )
    }

    private func catalog(destination: String, size: Int) async throws -> [CatalogHotel] {
        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = query.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
            ? "prod_hotels_zh"
            : "prod_hotels_en"
        guard let endpoint = URL(string: "https://\(algoliaApplicationID)-dsn.algolia.net/1/indexes/\(index)/query") else {
            throw AccorOfficialDirectError.invalidResponse
        }
        let payload: [String: Any] = [
            "query": query,
            "hitsPerPage": size,
            "attributesToRetrieve": [
                "objectID", "name", "brandLabel", "brand", "stars", "rating", "localization",
                "freeAmenities", "paidAmenities", "mediaCatalog", "medias", "description",
                "enhancedDescription", "labels", "thematics"
            ],
            "filters": "status:OPEN"
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue(algoliaApplicationID, forHTTPHeaderField: "X-Algolia-Application-Id")
        request.setValue(algoliaSearchKey, forHTTPHeaderField: "X-Algolia-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://all.accor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://all.accor.com/", forHTTPHeaderField: "Referer")
        let data = try await Self.data(for: request, session: session)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["hits"] as? [[String: Any]] else {
            throw AccorOfficialDirectError.invalidResponse
        }
        return rows.compactMap(Self.catalogHotel).prefix(size).map { $0 }
    }

    private nonisolated static func fetchRate(
        hotelCode: String,
        checkIn: Date,
        checkOut: Date,
        adults: Int,
        childrenAges: [Int],
        session: URLSession,
        endpoint: URL,
        apiKey: String
    ) async throws -> Rate? {
        let variables: [String: Any] = [
            "hotelOffersHotelId": hotelCode,
            "dateIn": dayFormatter.string(from: checkIn),
            "dateOut": dayFormatter.string(from: checkOut),
            "nbAdults": min(max(adults, 1), 8),
            "childrenAges": childrenAges,
            "selectionStep": 0,
            "countryMarket": "CN",
            "currency": "CNY",
            "offersSelectionFilters": [
                "cancellationPolicies": NSNull(),
                "isAccessible": false,
                "mealPlans": NSNull()
            ],
            "concession": NSNull(),
            "use": "NIGHT",
            "hideMemberRate": false,
            "selection": []
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "operationName": "HotelPageHot",
            "query": hotelOffersQuery,
            "variables": variables
        ])
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("all.accor", forHTTPHeaderField: "app-id")
        request.setValue("1.39.1", forHTTPHeaderField: "app-version")
        request.setValue("all.accor", forHTTPHeaderField: "clientid")
        request.setValue("zh", forHTTPHeaderField: "lang")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://all.accor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://all.accor.com/", forHTTPHeaderField: "Referer")
        let data = try await Self.data(for: request, session: session)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataRoot = root["data"] as? [String: Any],
              let hotelOffers = dataRoot["hotelOffers"] as? [String: Any],
              let availability = hotelOffers["availability"] as? [String: Any],
              string(availability["status"]) == "AVAILABLE",
              let selection = hotelOffers["offersSelection"] as? [String: Any],
              let offers = selection["offers"] as? [[String: Any]] else { return nil }
        let candidates: [(Int, [String: Any])] = offers.compactMap { offer in
            guard let pricing = offer["pricing"] as? [String: Any],
                  let main = pricing["main"] as? [String: Any],
                  let amount = number(main["amount"]), amount > 0 else { return nil }
            return (Int(amount.rounded()), offer)
        }
        guard let (amount, offer) = candidates.min(by: { $0.0 < $1.0 }),
              let pricing = offer["pricing"] as? [String: Any],
              let main = pricing["main"] as? [String: Any] else { return nil }
        let cancellation = ((main["simplifiedPolicies"] as? [String: Any])?["cancellation"] as? [String: Any])
        return Rate(
            totalAmountCNY: amount,
            roomName: optionalString((offer["accommodation"] as? [String: Any])?["code"]),
            mealPlan: optionalString((offer["mealPlan"] as? [String: Any])?["label"]),
            cancellationPolicy: optionalString(cancellation?["label"])
        )
    }

    private nonisolated static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AccorOfficialDirectError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AccorOfficialDirectError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AccorOfficialDirectError.httpFailure(http.statusCode)
        }
        return data
    }

    private static func catalogHotel(_ row: [String: Any]) -> CatalogHotel? {
        let code = string(row["objectID"])
        let name = string(row["name"])
        guard !code.isEmpty, name.count >= 2 else { return nil }
        let localization = row["localization"] as? [String: Any]
        let address = localization?["address"] as? [String: Any]
        let gps = localization?["gps"] as? [String: Any]
        let latitude = number(gps?["lat"])
        let longitude = number(gps?["lng"])
        let coordinate: Coordinate? = if let latitude, let longitude,
                                         (-90...90).contains(latitude), (-180...180).contains(longitude) {
            Coordinate(latitude: latitude, longitude: longitude)
        } else { nil }
        let rating = row["rating"] as? [String: Any]
        let catalog = row["mediaCatalog"] as? [String: Any]
        let medias = row["medias"] as? [String: Any]
        return CatalogHotel(
            code: code,
            name: name,
            brand: string(row["brandLabel"] ?? row["brand"]).nilIfEmpty,
            address: [string(address?["street"] ?? address?["line1"]), string(address?["city"])]
                .filter { !$0.isEmpty }.joined(separator: "，"),
            coordinate: coordinate,
            starRating: number(row["stars"]),
            guestRating: number(rating?["score"]),
            description: string(row["enhancedDescription"] ?? row["description"]).nilIfEmpty,
            imageURL: url(catalog?["1024x768"] ?? medias?["dmUrlCrop3by2"]),
            amenities: uniqueStrings(strings(row["freeAmenities"]) + strings(row["paidAmenities"])),
            tags: uniqueStrings(strings(row["labels"]) + strings(row["thematics"]))
        )
    }

    private static func bookingURL(hotelCode: String, checkIn: Date, checkOut: Date, adults: Int) -> URL? {
        var components = URLComponents(string: "https://all.accor.com/ssr/app/accor/rates")
        components?.queryItems = [
            URLQueryItem(name: "hotelCode", value: hotelCode),
            URLQueryItem(name: "checkIn", value: dayFormatter.string(from: checkIn)),
            URLQueryItem(name: "checkOut", value: dayFormatter.string(from: checkOut)),
            URLQueryItem(name: "numberOfRooms", value: "1"),
            URLQueryItem(name: "adults", value: String(min(max(adults, 1), 8)))
        ]
        return components?.url
    }

    private nonisolated static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        let raw = string(value)
        if let value = Double(raw) { return value }
        guard let match = raw.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(raw[match])
    }

    private nonisolated static func optionalString(_ value: Any?) -> String? {
        let value = string(value)
        return value.isEmpty ? nil : value
    }

    private static func strings(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { item in
            if let dictionary = item as? [String: Any] {
                return string(dictionary["label"] ?? dictionary["value"] ?? dictionary["name"]).nilIfEmpty
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
        let resolved = raw.hasPrefix("//") ? "https:\(raw)" : raw
        guard let url = URL(string: resolved), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    private nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private nonisolated static let hotelOffersQuery = """
        query HotelPageHot(
          $hotelOffersHotelId: String!, $dateIn: Date!, $dateOut: Date!,
          $nbAdults: PositiveInt!, $childrenAges: [NonNegativeInt!],
          $countryMarket: String!, $currency: String!,
          $offersSelectionFilters: OffersSelectionFilters,
          $use: BestOfferUse, $selectionStep: Int,
          $concession: BestOfferConcession, $hideMemberRate: Boolean,
          $selection: [OfferSelectionInput!]
        ) {
          hotelOffers(
            hotelId: $hotelOffersHotelId, dateIn: $dateIn, dateOut: $dateOut,
            nbAdults: $nbAdults, childrenAges: $childrenAges,
            countryMarket: $countryMarket, currency: $currency,
            use: $use, concession: $concession, hideMemberRate: $hideMemberRate
          ) {
            offersSelection(selectionStep: $selectionStep, filters: $offersSelectionFilters, selection: $selection) {
              offers {
                accommodation { code }
                pricing { main { amount simplifiedPolicies { cancellation { label } } } }
                mealPlan { label }
              }
            }
            availability { status }
          }
        }
        """
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
