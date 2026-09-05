import Foundation
import WebKit

enum QunarFlightDirectError: LocalizedError, Equatable {
    case missingDates
    case invalidRoute
    case navigationTimedOut
    case pageFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDates:
            "先添上出发日期，才能读取航班价格。"
        case .invalidRoute:
            "去哪儿航班页暂时无法识别这段出发与抵达城市。"
        case .navigationTimedOut:
            "去哪儿航班页加载超时，请稍后再试。"
        case let .pageFailed(message):
            "去哪儿航班价格暂时没有抵达：\(message)"
        }
    }
}

struct QunarFlightPageSnapshot: Equatable, Sendable {
    struct Card: Equatable, Sendable {
        var priceText: String
        var departureTime: String
        var arrivalTime: String
        var departurePlace: String
        var arrivalPlace: String
        var airline: String
        var flightNumber: String
        var durationText: String
        var detailText: String
    }

    var cards: [Card]
    var responseBodies: [String]
    var pageText: String
    var pageURL: URL?
}

/// Reads the normal public Qunar mobile flight page in WebKit. It shares the same
/// website data store as ProviderLoginView, so a session explicitly saved by the
/// traveller can be reused without AnyTravel ever seeing the entered password.
@MainActor
struct QunarFlightDirectClient {
    typealias PageLoader = @MainActor @Sendable (URL) async throws -> QunarFlightPageSnapshot

    private struct Journey {
        var direction: TransportDirection
        var date: Date
        var departureCity: String
        var arrivalCity: String
    }

    struct ParsedFlight: Hashable {
        var amountCNY: Int
        var departureTime: String
        var arrivalTime: String
        var departurePlace: String
        var arrivalPlace: String
        var airline: String
        var flightNumber: String
        var durationMinutes: Int?
    }

    private let pageLoader: PageLoader
    private let resultLimit: Int
    private let requiresSavedSession: Bool

    init(resultLimit: Int = 8) {
        self.pageLoader = { url in
            try await QunarFlightWebPageLoader.load(url)
        }
        self.resultLimit = min(max(resultLimit, 1), 12)
        self.requiresSavedSession = true
    }

    init(resultLimit: Int = 8, pageLoader: @escaping PageLoader) {
        self.pageLoader = pageLoader
        self.resultLimit = min(max(resultLimit, 1), 12)
        self.requiresSavedSession = false
    }

    func enrichTransportOptions(
        _ currentOptions: [TransportOption],
        origin: String,
        destination: String,
        logistics: TripLogistics,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?
    ) async throws -> PricingEnrichmentResult<[TransportOption]> {
        if requiresSavedSession && !ProviderSessionStore.hasSavedSession(.qunar) {
            return PricingEnrichmentResult(
                value: currentOptions,
                receivedCount: 0,
                capturedAt: .now,
                isCached: false,
                issues: []
            )
        }
        guard let departureDate = logistics.startDate else { throw QunarFlightDirectError.missingDates }
        let originCity = Self.normalizedCity(origin)
        let destinationCity = Self.flightCity(
            destination,
            accessPoints: accessPoints,
            fallback: currentOptions.first {
                $0.mode == .flight && $0.journeyDirection == .outbound
            }?.arrivalAccessPoint
        )
        guard !originCity.isEmpty, !destinationCity.isEmpty else { throw QunarFlightDirectError.invalidRoute }

        var journeys = [
            Journey(
                direction: .outbound,
                date: departureDate,
                departureCity: originCity,
                arrivalCity: destinationCity
            )
        ]
        if let returnDate = logistics.endDate {
            journeys.append(
                Journey(
                    direction: .returnTrip,
                    date: returnDate,
                    departureCity: destinationCity,
                    arrivalCity: originCity
                )
            )
        }

        let capturedAt = Date.now
        var options = currentOptions
        var issues: [PricingProviderIssue] = []
        var receivedCount = 0
        for journey in journeys {
            do {
                let url = try Self.searchURL(for: journey, travelers: logistics.effectiveAdults + logistics.effectiveChildrenAges.count)
                let snapshot = try await pageLoader(url)
                guard !Task.isCancelled else { throw CancellationError() }
                let parsed = Self.parseFlights(snapshot: snapshot)
                let minimum = Self.minimumPrice(in: snapshot)
                let live = Self.makeOptions(
                    parsedFlights: Array(parsed.prefix(resultLimit)),
                    pageMinimum: minimum,
                    journey: journey,
                    bookingURL: snapshot.pageURL ?? url,
                    currentOptions: options,
                    accessPoints: accessPoints,
                    accommodation: accommodation,
                    capturedAt: capturedAt
                )
                if live.isEmpty {
                    issues.append(Self.issue(for: snapshot, journey: journey))
                } else {
                    receivedCount += live.reduce(0) { count, option in
                        count + option.quotes.filter { $0.provider == .qunar && $0.amountCNY != nil }.count
                    }
                    options = NativeFlightOptionMerger.merging(
                        live,
                        into: options,
                        provider: .qunar,
                        direction: journey.direction
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                issues.append(
                    PricingProviderIssue(
                        provider: "qunar",
                        status: "failed",
                        detail: "\(journey.direction.title) \(journey.departureCity)→\(journey.arrivalCity)：\(error.localizedDescription)"
                    )
                )
            }
        }

        options.sort(by: Self.compareOptions)
        return PricingEnrichmentResult(
            value: options,
            receivedCount: receivedCount,
            capturedAt: capturedAt,
            isCached: false,
            issues: issues
        )
    }

    private static func makeOptions(
        parsedFlights: [ParsedFlight],
        pageMinimum: Int?,
        journey: Journey,
        bookingURL: URL,
        currentOptions: [TransportOption],
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?,
        capturedAt: Date
    ) -> [TransportOption] {
        if !parsedFlights.isEmpty {
            return parsedFlights.map { flight in
                let localAirportName = journey.direction == .outbound
                    ? flight.arrivalPlace
                    : flight.departurePlace
                let accessPoint = bestAirport(
                    named: localAirportName,
                    in: accessPoints,
                    fallback: currentOptions.first {
                        $0.mode == .flight && $0.journeyDirection == journey.direction
                    }?.arrivalAccessPoint
                )
                let transferMeters = accessPoint.flatMap { point in
                    accommodation.map { LogisticsSearchService.distance(from: point.coordinate, to: $0.coordinate) }
                }
                let quote = ProviderQuote(
                    provider: .qunar,
                    amountCNY: flight.amountCNY,
                    unit: .perPerson,
                    kind: .live,
                    capturedAt: capturedAt,
                    bookingURL: bookingURL,
                    note: "去哪儿当前航班页展示的单程起价；税费、舱位和退改条件以提交订单前为准",
                    displayPriceText: "¥\(flight.amountCNY)起",
                    sourceLabel: "去哪儿网页会话",
                    availability: "舱位以去哪儿页面为准"
                )
                var reasons = ["\(flight.departureTime)–\(flight.arrivalTime) · 去哪儿当前页面"]
                if let accessPoint, let transferMeters {
                    reasons.append(
                        journey.direction == .outbound
                            ? "\(accessPoint.name)到住宿约\(transferMeters.anyTravelDistanceText)"
                            : "住宿到\(accessPoint.name)约\(transferMeters.anyTravelDistanceText)"
                    )
                }
                let carrier = [flight.airline, flight.flightNumber]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let route = "\(flight.departurePlace.nonEmpty ?? journey.departureCity)→\(flight.arrivalPlace.nonEmpty ?? journey.arrivalCity)"
                return TransportOption(
                    mode: .flight,
                    title: carrier.isEmpty ? route : "\(carrier) · \(route)",
                    originName: flight.departurePlace.nonEmpty ?? journey.departureCity,
                    destinationName: flight.arrivalPlace.nonEmpty ?? journey.arrivalCity,
                    direction: journey.direction,
                    durationMinutes: flight.durationMinutes,
                    departureTime: date(day: journey.date, clock: flight.departureTime),
                    arrivalTime: arrivalDate(day: journey.date, departure: flight.departureTime, arrival: flight.arrivalTime),
                    arrivalAccessPoint: accessPoint,
                    hotelTransferMeters: transferMeters,
                    quotes: [quote],
                    recommendationReasons: reasons,
                    isRecommended: false
                )
            }
        }

        guard let pageMinimum else { return [] }
        var option = currentOptions.first {
            $0.mode == .flight && $0.journeyDirection == journey.direction
        } ?? TransportOption(
            mode: .flight,
            title: "航班抵达 \(journey.arrivalCity)",
            originName: journey.departureCity,
            destinationName: journey.arrivalCity,
            direction: journey.direction
        )
        option.title = "去哪儿 · \(journey.departureCity)→\(journey.arrivalCity) 当日起价"
        option.originName = journey.departureCity
        option.destinationName = journey.arrivalCity
        option.quotes.removeAll { $0.provider == .qunar }
        option.quotes.insert(
            ProviderQuote(
                provider: .qunar,
                amountCNY: pageMinimum,
                unit: .perPerson,
                kind: .live,
                capturedAt: capturedAt,
                bookingURL: bookingURL,
                note: "去哪儿当前搜索页返回的当日最低起价；具体航班、税费与余位请进入页面选择",
                displayPriceText: "¥\(pageMinimum)起",
                sourceLabel: "去哪儿公开航班页",
                availability: "当前页面有报价"
            ),
            at: 0
        )
        option.recommendationReasons = ["已取得去哪儿当日最低起价", "进入渠道后选择具体时刻与舱位"]
        return [option]
    }

    private static func issue(for snapshot: QunarFlightPageSnapshot, journey: Journey) -> PricingProviderIssue {
        let text = snapshot.pageText.lowercased()
        if text.contains("安全验证") || text.contains("验证码") || text.contains("访问过于频繁") || text.contains("操作频繁") {
            return PricingProviderIssue(
                provider: "qunar",
                status: "verification_required",
                detail: "\(journey.direction.title) \(journey.departureCity)→\(journey.arrivalCity)"
            )
        }
        if text.contains("没有查询到符合条件的航班") || text.contains("暂无符合") || text.contains("暂无航班") {
            return PricingProviderIssue(
                provider: "qunar",
                status: "no_matching_quotes",
                detail: "\(journey.direction.title) \(journey.departureCity)→\(journey.arrivalCity) 当天暂无可展示航班"
            )
        }
        return PricingProviderIssue(
            provider: "qunar",
            status: "no_visible_cards",
            detail: "\(journey.direction.title) \(journey.departureCity)→\(journey.arrivalCity)"
        )
    }

    static func parseFlights(snapshot: QunarFlightPageSnapshot) -> [ParsedFlight] {
        var flights = snapshot.cards.compactMap { card -> ParsedFlight? in
            guard let amount = amount(in: card.priceText),
                  let departure = clock(in: card.departureTime),
                  let arrival = clock(in: card.arrivalTime) else { return nil }
            let flightNumber = card.flightNumber.nonEmpty
                ?? firstMatch(in: card.detailText + " " + card.airline, pattern: #"[A-Z0-9]{2}\s?\d{3,4}"#)
                ?? ""
            return ParsedFlight(
                amountCNY: amount,
                departureTime: departure,
                arrivalTime: arrival,
                departurePlace: card.departurePlace.trimmingCharacters(in: .whitespacesAndNewlines),
                arrivalPlace: card.arrivalPlace.trimmingCharacters(in: .whitespacesAndNewlines),
                airline: card.airline.trimmingCharacters(in: .whitespacesAndNewlines),
                flightNumber: flightNumber,
                durationMinutes: durationMinutes(in: card.durationText + " " + card.detailText)
            )
        }

        for body in snapshot.responseBodies {
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectFlights(from: root, into: &flights)
        }

        var seen = Set<String>()
        return flights.filter { flight in
            let key = [
                flight.departureTime,
                flight.arrivalTime,
                flight.departurePlace,
                flight.arrivalPlace,
                flight.flightNumber,
                String(flight.amountCNY)
            ].joined(separator: "|").lowercased()
            return seen.insert(key).inserted
        }
        .sorted {
            if $0.amountCNY != $1.amountCNY { return $0.amountCNY < $1.amountCNY }
            return $0.departureTime < $1.departureTime
        }
    }

    static func minimumPrice(in snapshot: QunarFlightPageSnapshot) -> Int? {
        let cardPrices = snapshot.cards.compactMap { amount(in: $0.priceText) }
        var prices = cardPrices
        for body in snapshot.responseBodies {
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectMinimumPrices(from: root, into: &prices)
        }
        return prices.filter { (40...100_000).contains($0) }.min()
    }

    private static func collectFlights(from value: Any, into flights: inout [ParsedFlight]) {
        if let dictionary = value as? [String: Any] {
            let departure = stringValue(dictionary["depTime"] ?? dictionary["departureTime"])
            let arrival = stringValue(dictionary["arrTime"] ?? dictionary["arrivalTime"])
            let price = amountValue(dictionary["minPrice"] ?? dictionary["price"] ?? dictionary["salePrice"])
            if let departureClock = clock(in: departure),
               let arrivalClock = clock(in: arrival),
               let price,
               (40...100_000).contains(price) {
                flights.append(
                    ParsedFlight(
                        amountCNY: price,
                        departureTime: departureClock,
                        arrivalTime: arrivalClock,
                        departurePlace: stringValue(
                            dictionary["depAirport"] ?? dictionary["departureAirport"] ?? dictionary["depStation"]
                        ),
                        arrivalPlace: stringValue(
                            dictionary["arrAirport"] ?? dictionary["arrivalAirport"] ?? dictionary["arrStation"]
                        ),
                        airline: stringValue(dictionary["name"] ?? dictionary["airlineName"] ?? dictionary["airline"]),
                        flightNumber: stringValue(
                            dictionary["binfo"] ?? dictionary["flightNo"] ?? dictionary["flightNumber"]
                        ),
                        durationMinutes: durationValue(
                            dictionary["totalDuration"] ?? dictionary["duration"] ?? dictionary["flyTime"]
                        )
                    )
                )
            }
            for child in dictionary.values { collectFlights(from: child, into: &flights) }
        } else if let array = value as? [Any] {
            for child in array { collectFlights(from: child, into: &flights) }
        } else if let string = value as? String,
                  let data = string.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: data) {
            collectFlights(from: nested, into: &flights)
        }
    }

    private static func collectMinimumPrices(from value: Any, into prices: inout [Int]) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if key.lowercased() == "minprice", let price = amountValue(child) {
                    prices.append(price)
                }
                collectMinimumPrices(from: child, into: &prices)
            }
        } else if let array = value as? [Any] {
            for child in array { collectMinimumPrices(from: child, into: &prices) }
        } else if let string = value as? String,
                  let data = string.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: data) {
            collectMinimumPrices(from: nested, into: &prices)
        }
    }

    private static func searchURL(for journey: Journey, travelers: Int) throws -> URL {
        var components = URLComponents(string: "https://touch.qunar.com/ncs/page/flightlist")!
        components.queryItems = [
            URLQueryItem(name: "depCity", value: journey.departureCity),
            URLQueryItem(name: "arrCity", value: journey.arrivalCity),
            URLQueryItem(name: "goDate", value: dayFormatter.string(from: journey.date)),
            URLQueryItem(name: "from", value: "AnyTravel_public_flight_search"),
            URLQueryItem(name: "adultNum", value: String(max(travelers, 1))),
            URLQueryItem(name: "childNum", value: "0"),
            URLQueryItem(name: "babyNum", value: "0"),
            URLQueryItem(name: "cabinType", value: "0")
        ]
        guard let url = components.url else { throw QunarFlightDirectError.invalidRoute }
        return url
    }

    private static func flightCity(_ city: String, accessPoints: [AccessPoint], fallback: AccessPoint?) -> String {
        let normalized = normalizedCity(city)
        let airports = accessPoints.filter { $0.kind == .airport }
        if airports.contains(where: { normalizedAirportName($0.name).contains(normalized) }) {
            return normalized
        }
        for airport in airports + [fallback].compactMap({ $0 }) {
            let airportName = normalizedAirportName(airport.name)
            if let match = airportCityAliases.first(where: { airportName.contains($0.key) }) {
                return match.value
            }
        }
        return normalized
    }

    private static func bestAirport(named name: String, in points: [AccessPoint], fallback: AccessPoint?) -> AccessPoint? {
        let airports = points.filter { $0.kind == .airport }
        let target = normalizedAirportName(name)
        if !target.isEmpty {
            if let exact = airports.first(where: { normalizedAirportName($0.name) == target }) { return exact }
            if let close = airports.first(where: {
                let candidate = normalizedAirportName($0.name)
                return candidate.contains(target) || target.contains(candidate)
            }) { return close }
        }
        return fallback ?? airports.first
    }

    private static func normalizedCity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "特别行政区", with: "")
            .replacingOccurrences(of: "壮族自治区", with: "")
            .replacingOccurrences(of: "回族自治区", with: "")
            .replacingOccurrences(of: "维吾尔自治区", with: "")
            .replacingOccurrences(of: "自治区", with: "")
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "市", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedAirportName(_ value: String) -> String {
        value.replacingOccurrences(of: "国际机场", with: "")
            .replacingOccurrences(of: "机场", with: "")
            .replacingOccurrences(of: "航站楼", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func amount(in text: String) -> Int? {
        let matches = matches(in: text, pattern: #"\d{2,6}(?:\.\d+)?"#)
        return matches.compactMap(Double.init).map { Int($0.rounded()) }
            .first { (40...100_000).contains($0) }
    }

    private static func amountValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return Int(number.doubleValue.rounded()) }
        if let string = value as? String { return amount(in: string) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        if let value = value as? [String: Any] {
            return stringValue(value["name"] ?? value["displayName"] ?? value["title"] ?? value["code"])
        }
        return ""
    }

    private static func clock(in text: String) -> String? {
        firstMatch(in: text, pattern: #"(?:[01]?\d|2[0-3]):[0-5]\d"#)
    }

    private static func durationMinutes(in text: String) -> Int? {
        let hours = firstMatch(in: text, pattern: #"(\d+)\s*(?:小时|h|H)"#, group: 1).flatMap(Int.init) ?? 0
        let minutes = firstMatch(in: text, pattern: #"(\d+)\s*(?:分钟|分|min)"#, group: 1).flatMap(Int.init) ?? 0
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }

    private static func durationValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let raw = number.intValue
            if raw <= 0 { return nil }
            return raw > 1_440 ? Int((Double(raw) / 60).rounded()) : raw
        }
        if let string = value as? String {
            if let parsed = durationMinutes(in: string) { return parsed }
            if let raw = Int(string), raw > 0 { return raw > 1_440 ? Int((Double(raw) / 60).rounded()) : raw }
        }
        return nil
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let value = Range(match.range, in: text) else { return nil }
            return String(text[value])
        }
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range]).replacingOccurrences(of: " ", with: "")
    }

    private static func date(day: Date, clock: String) -> Date? {
        dateTimeFormatter.date(from: "\(dayFormatter.string(from: day)) \(clock)")
    }

    private static func arrivalDate(day: Date, departure: String, arrival: String) -> Date? {
        guard let departureDate = date(day: day, clock: departure),
              var arrivalDate = date(day: day, clock: arrival) else { return nil }
        if arrivalDate < departureDate {
            arrivalDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate
        }
        return arrivalDate
    }

    private static func compareOptions(_ lhs: TransportOption, _ rhs: TransportOption) -> Bool {
        if lhs.journeyDirection != rhs.journeyDirection { return lhs.journeyDirection == .outbound }
        if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
        let lhsLive = lhs.quotes.contains { $0.amountCNY != nil } ? 0 : 1
        let rhsLive = rhs.quotes.contains { $0.amountCNY != nil } ? 0 : 1
        if lhsLive != rhsLive { return lhsLive < rhsLive }
        let lhsPrice = lhs.quotes.compactMap(\.amountCNY).min() ?? .max
        let rhsPrice = rhs.quotes.compactMap(\.amountCNY).min() ?? .max
        if lhsPrice != rhsPrice { return lhsPrice < rhsPrice }
        return (lhs.durationMinutes ?? .max) < (rhs.durationMinutes ?? .max)
    }

    private static let airportCityAliases: [(key: String, value: String)] = [
        ("苏南硕放", "无锡"), ("虹桥", "上海"), ("浦东", "上海"),
        ("首都", "北京"), ("大兴", "北京"), ("双流", "成都"), ("天府", "成都"),
        ("滨海", "天津"), ("栎社", "宁波"), ("萧山", "杭州"), ("白云", "广州"),
        ("宝安", "深圳"), ("禄口", "南京"), ("天河", "武汉"), ("咸阳", "西安"),
        ("黄花", "长沙"), ("高崎", "厦门"), ("翔安", "厦门"), ("凤凰", "三亚"),
        ("美兰", "海口"), ("长水", "昆明"), ("江北", "重庆"), ("胶东", "青岛"),
        ("流亭", "青岛"), ("新郑", "郑州"), ("遥墙", "济南"), ("桃仙", "沈阳"),
        ("周水子", "大连"), ("太平", "哈尔滨"), ("龙嘉", "长春"), ("武宿", "太原"),
        ("正定", "石家庄"), ("昌北", "南昌"), ("新桥", "合肥"), ("龙洞堡", "贵阳"),
        ("吴圩", "南宁"), ("中川", "兰州"), ("地窝堡", "乌鲁木齐"),
        ("贡嘎", "拉萨"), ("金湾", "珠海")
    ]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

@MainActor
private enum QunarFlightWebPageLoader {
    static func load(_ url: URL) async throws -> QunarFlightPageSnapshot {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: responseCaptureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = QunarNavigationWaiter()
        webView.navigationDelegate = navigation
        try await navigation.load(url, in: webView)

        var latest = QunarFlightPageSnapshot(cards: [], responseBodies: [], pageText: "", pageURL: url)
        for attempt in 0..<30 {
            guard !Task.isCancelled else { throw CancellationError() }
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(450))
            }
            latest = try await snapshot(from: webView)
            if !latest.cards.isEmpty || !latest.responseBodies.isEmpty {
                // Give the page a short second beat so lazy-rendered fare cards can settle.
                if attempt >= 2 { break }
            }
            if latest.pageText.contains("没有查询到符合条件的航班")
                || latest.pageText.contains("安全验证")
                || latest.pageText.contains("验证码") {
                break
            }
        }
        return latest
    }

    private static func snapshot(from webView: WKWebView) async throws -> QunarFlightPageSnapshot {
        let value = try await evaluate(extractionScript, in: webView)
        guard let data = value.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(WebEnvelope.self, from: data) else {
            throw QunarFlightDirectError.pageFailed("页面返回的数据无法解析")
        }
        return QunarFlightPageSnapshot(
            cards: envelope.cards.map {
                QunarFlightPageSnapshot.Card(
                    priceText: $0.priceText,
                    departureTime: $0.departureTime,
                    arrivalTime: $0.arrivalTime,
                    departurePlace: $0.departurePlace,
                    arrivalPlace: $0.arrivalPlace,
                    airline: $0.airline,
                    flightNumber: $0.flightNumber,
                    durationText: $0.durationText,
                    detailText: $0.detailText
                )
            },
            responseBodies: envelope.responses,
            pageText: envelope.pageText,
            pageURL: URL(string: envelope.pageURL) ?? webView.url
        )
    }

    private static func evaluate(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: QunarFlightDirectError.pageFailed(error.localizedDescription))
                } else if let value = value as? String {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: QunarFlightDirectError.pageFailed("页面脚本没有返回文本"))
                }
            }
        }
    }

    private struct WebEnvelope: Decodable {
        struct Card: Decodable {
            var priceText: String
            var departureTime: String
            var arrivalTime: String
            var departurePlace: String
            var arrivalPlace: String
            var airline: String
            var flightNumber: String
            var durationText: String
            var detailText: String
        }

        var cards: [Card]
        var responses: [String]
        var pageText: String
        var pageURL: String
    }

    private static let responseCaptureScript = #"""
    (() => {
      if (window.__anyTravelCaptureInstalled) return;
      window.__anyTravelCaptureInstalled = true;
      window.__anyTravelFlightResponses = [];
      const remember = (url, text) => {
        if (!String(url || '').includes('/flight/api/touchInnerList')) return;
        const body = String(text || '').slice(0, 600000);
        if (body && !window.__anyTravelFlightResponses.includes(body)) {
          window.__anyTravelFlightResponses.push(body);
          window.__anyTravelFlightResponses = window.__anyTravelFlightResponses.slice(-8);
        }
      };
      const originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function(...args) {
          return originalFetch.apply(this, args).then(response => {
            try {
              const url = response.url || args[0];
              response.clone().text().then(text => remember(url, text)).catch(() => {});
            } catch (_) {}
            return response;
          });
        };
      }
      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__anyTravelURL = url;
        return originalOpen.call(this, method, url, ...rest);
      };
      XMLHttpRequest.prototype.send = function(...args) {
        this.addEventListener('load', () => {
          try { remember(this.responseURL || this.__anyTravelURL, this.responseText); } catch (_) {}
        }, { once: true });
        return originalSend.apply(this, args);
      };
    })();
    """#

    private static let extractionScript = #"""
    (() => {
      const text = (root, selectors) => {
        for (const selector of selectors) {
          const element = root.querySelector(selector);
          const value = element && (element.innerText || element.textContent || '').trim();
          if (value) return value;
        }
        return '';
      };
      const rows = Array.from(document.querySelectorAll('.list-row.item, .list-row-rdw.item, [class*="flight-list"] [class*="list-row"]')).slice(0, 30);
      const cards = rows.map(row => ({
        priceText: text(row, ['.price-info', '[class*="price"]']),
        departureTime: text(row, ['.from-time', '[class*="from-time"]', '[class*="dep-time"]']),
        arrivalTime: text(row, ['.to-time', '[class*="to-time"]', '[class*="arr-time"]']),
        departurePlace: text(row, ['.from-place', '[class*="from-place"]', '[class*="dep-airport"]']),
        arrivalPlace: text(row, ['.to-place', '[class*="to-place"]', '[class*="arr-airport"]']),
        airline: text(row, ['.company1', '.company-info', '[class*="company"]', '[class*="airline"]']),
        flightNumber: text(row, ['[class*="flight-no"]', '[class*="flightNo"]']),
        durationText: text(row, ['.howlong', '[class*="duration"]', '[class*="howlong"]']),
        detailText: (row.innerText || row.textContent || '').trim().slice(0, 1200)
      }));
      return JSON.stringify({
        cards,
        responses: (window.__anyTravelFlightResponses || []).slice(-8),
        pageText: (document.body && (document.body.innerText || document.body.textContent) || '').slice(0, 12000),
        pageURL: location.href
      });
    })();
    """#
}

@MainActor
private final class QunarNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 20))
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(22))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(QunarFlightDirectError.navigationTimedOut))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(.failure(QunarFlightDirectError.pageFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(.failure(QunarFlightDirectError.pageFailed(error.localizedDescription)))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
