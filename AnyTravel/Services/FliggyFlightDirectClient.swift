import CryptoKit
import Foundation

enum FliggyFlightDirectError: LocalizedError, Equatable {
    case missingDates
    case airportCodeUnavailable(String)
    case invalidResponse
    case httpFailure(Int)
    case providerRejected(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingDates:
            "先添上出发日期，才能读取航班价格。"
        case let .airportCodeUnavailable(city):
            "暂时没有找到“\(city)”对应的民航城市代码。"
        case .invalidResponse:
            "飞猪航班页返回了无法识别的数据。"
        case let .httpFailure(status):
            "飞猪航班页暂时拒绝了请求（\(status)）。"
        case let .providerRejected(message):
            "飞猪航班页本次没有返回报价：\(message)"
        case let .network(message):
            "暂时没有接上飞猪航班页：\(message)"
        }
    }
}

struct FliggyFlightOffer: Equatable, Hashable, Sendable {
    var price: Int
    var airline: String
    var flightNumber: String
    var departureTime: String
    var arrivalTime: String
    var departureAirport: String
    var arrivalAirport: String
    var durationMinutes: Int?
}

struct FliggyFlightSearchResult: Equatable, Sendable {
    var offers: [FliggyFlightOffer]
    var lowestPrice: Int?
}

/// Uses the public mobile MTOP page contract. The first request receives the
/// normal anonymous H5 cookie and the second request signs with that cookie.
/// No account token, device fingerprint override, or private app credential is used.
@MainActor
struct FliggyFlightDirectClient {
    typealias Search = @MainActor @Sendable (_ departureCode: String, _ arrivalCode: String, _ date: Date) async throws -> FliggyFlightSearchResult

    private struct Journey {
        var direction: TransportDirection
        var date: Date
        var departureCity: String
        var arrivalCity: String
        var departureCode: String
        var arrivalCode: String
    }

    private let resultLimit: Int
    private let search: Search

    init(
        resultLimit: Int = 8,
        search: @escaping Search = { departureCode, arrivalCode, date in
            try await FliggyMTOPFlightPage.search(
                departureCode: departureCode,
                arrivalCode: arrivalCode,
                date: date
            )
        }
    ) {
        self.resultLimit = min(max(resultLimit, 1), 12)
        self.search = search
    }

    func enrichTransportOptions(
        _ currentOptions: [TransportOption],
        origin: String,
        destination: String,
        logistics: TripLogistics,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?
    ) async throws -> PricingEnrichmentResult<[TransportOption]> {
        guard let departureDate = logistics.startDate else { throw FliggyFlightDirectError.missingDates }
        let originCity = Self.normalizedCity(origin)
        let destinationCity = Self.normalizedCity(destination)
        guard let originCode = Self.airportCode(for: originCity, accessPoints: [], fallback: nil) else {
            throw FliggyFlightDirectError.airportCodeUnavailable(originCity)
        }
        let fallbackAirport = currentOptions.first {
            $0.mode == .flight && $0.journeyDirection == .outbound
        }?.arrivalAccessPoint
        guard let destinationCode = Self.airportCode(
            for: destinationCity,
            accessPoints: accessPoints,
            fallback: fallbackAirport
        ) else {
            throw FliggyFlightDirectError.airportCodeUnavailable(destinationCity)
        }

        var journeys = [
            Journey(
                direction: .outbound,
                date: departureDate,
                departureCity: originCity,
                arrivalCity: destinationCity,
                departureCode: originCode,
                arrivalCode: destinationCode
            )
        ]
        if let returnDate = logistics.endDate {
            journeys.append(
                Journey(
                    direction: .returnTrip,
                    date: returnDate,
                    departureCity: destinationCity,
                    arrivalCity: originCity,
                    departureCode: destinationCode,
                    arrivalCode: originCode
                )
            )
        }

        var options = currentOptions
        var receivedCount = 0
        var issues: [PricingProviderIssue] = []
        let capturedAt = Date.now
        for journey in journeys {
            do {
                let result = try await search(journey.departureCode, journey.arrivalCode, journey.date)
                guard !Task.isCancelled else { throw CancellationError() }
                let incoming = Self.options(
                    from: result,
                    journey: journey,
                    accessPoints: accessPoints,
                    accommodation: accommodation,
                    capturedAt: capturedAt,
                    resultLimit: resultLimit
                )
                if incoming.isEmpty {
                    issues.append(
                        PricingProviderIssue(
                            provider: "fliggy",
                            status: "no_matching_quotes",
                            detail: "\(journey.direction.title) \(journey.departureCity)→\(journey.arrivalCity) 当天暂无可展示航班"
                        )
                    )
                    continue
                }
                receivedCount += incoming.flatMap(\.quotes).filter { $0.amountCNY != nil }.count
                options = NativeFlightOptionMerger.merging(
                    incoming,
                    into: options,
                    provider: .fliggy,
                    direction: journey.direction
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                issues.append(
                    PricingProviderIssue(
                        provider: "fliggy",
                        status: "failed",
                        detail: "\(journey.direction.title) \(journey.departureCity)→\(journey.arrivalCity)：\(error.localizedDescription)"
                    )
                )
            }
        }

        return PricingEnrichmentResult(
            value: options,
            receivedCount: receivedCount,
            capturedAt: capturedAt,
            isCached: false,
            issues: issues
        )
    }

    private static func options(
        from result: FliggyFlightSearchResult,
        journey: Journey,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?,
        capturedAt: Date,
        resultLimit: Int
    ) -> [TransportOption] {
        let bookingURL = bookingURL(for: journey)
        let detailed = Array(result.offers.prefix(resultLimit)).map { offer in
            let localAirportName = journey.direction == .outbound
                ? offer.arrivalAirport
                : offer.departureAirport
            let accessPoint = bestAirport(named: localAirportName, in: accessPoints)
            let transferMeters = accessPoint.flatMap { point in
                accommodation.map { LogisticsSearchService.distance(from: point.coordinate, to: $0.coordinate) }
            }
            let quote = ProviderQuote(
                provider: .fliggy,
                amountCNY: offer.price,
                unit: .perPerson,
                kind: .live,
                capturedAt: capturedAt,
                bookingURL: bookingURL,
                note: "飞猪当前航班搜索返回的单程起价；税费、舱位和退改条件以提交订单前为准",
                displayPriceText: "¥\(offer.price)起",
                sourceLabel: "飞猪公开航班页",
                availability: "舱位以飞猪结算页为准"
            )
            var reasons = ["\(offer.departureTime)–\(offer.arrivalTime) · 飞猪当前报价"]
            if let accessPoint, let transferMeters {
                reasons.append(
                    journey.direction == .outbound
                        ? "\(accessPoint.name)到住宿约\(transferMeters.anyTravelDistanceText)"
                        : "住宿到\(accessPoint.name)约\(transferMeters.anyTravelDistanceText)"
                )
            }
            let carrier = [offer.airline, offer.flightNumber]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return TransportOption(
                mode: .flight,
                title: carrier.isEmpty ? "\(journey.departureCity)→\(journey.arrivalCity)" : carrier,
                originName: offer.departureAirport.nonEmpty ?? journey.departureCity,
                destinationName: offer.arrivalAirport.nonEmpty ?? journey.arrivalCity,
                direction: journey.direction,
                durationMinutes: offer.durationMinutes,
                departureTime: date(day: journey.date, clock: offer.departureTime),
                arrivalTime: arrivalDate(day: journey.date, departure: offer.departureTime, arrival: offer.arrivalTime),
                arrivalAccessPoint: accessPoint,
                hotelTransferMeters: transferMeters,
                quotes: [quote],
                recommendationReasons: reasons
            )
        }
        if !detailed.isEmpty { return detailed }

        guard let lowestPrice = result.lowestPrice, lowestPrice > 0 else { return [] }
        return [
            TransportOption(
                mode: .flight,
                title: "飞猪 · \(journey.departureCity)→\(journey.arrivalCity) 当日起价",
                originName: journey.departureCity,
                destinationName: journey.arrivalCity,
                direction: journey.direction,
                quotes: [
                    ProviderQuote(
                        provider: .fliggy,
                        amountCNY: lowestPrice,
                        unit: .perPerson,
                        kind: .live,
                        capturedAt: capturedAt,
                        bookingURL: bookingURL,
                        note: "飞猪当前搜索返回的当日最低起价；进入渠道后选择具体航班与舱位",
                        displayPriceText: "¥\(lowestPrice)起",
                        sourceLabel: "飞猪公开航班页",
                        availability: "当前搜索有报价"
                    )
                ],
                recommendationReasons: ["已取得飞猪当日最低起价", "进入渠道后选择具体时刻与舱位"]
            )
        ]
    }

    private static func airportCode(
        for city: String,
        accessPoints: [AccessPoint],
        fallback: AccessPoint?
    ) -> String? {
        let raw = city.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if raw.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil { return raw }
        let candidates = [city] + accessPoints.filter { $0.kind == .airport }.map(\.name) + [fallback?.name].compactMap { $0 }
        for candidate in candidates {
            let normalized = normalizedAirportName(candidate)
            if let match = airportCodes.first(where: { normalized.contains($0.alias) }) {
                return match.code
            }
        }
        return nil
    }

    private static func bestAirport(named name: String, in accessPoints: [AccessPoint]) -> AccessPoint? {
        let airports = accessPoints.filter { $0.kind == .airport }
        let target = normalizedAirportName(name)
        if let match = airports.first(where: {
            let candidate = normalizedAirportName($0.name)
            return candidate == target || candidate.contains(target) || target.contains(candidate)
        }) {
            return match
        }
        return airports.first
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
        normalizedCity(value)
            .replacingOccurrences(of: "国际机场", with: "")
            .replacingOccurrences(of: "机场", with: "")
            .replacingOccurrences(of: "航站楼", with: "")
            .replacingOccurrences(of: #"T\d+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func bookingURL(for journey: Journey) -> URL? {
        var components = URLComponents(string: "https://h5.m.taobao.com/trip/flight/search/index.html")
        components?.queryItems = [
            URLQueryItem(name: "depCityCode", value: journey.departureCode),
            URLQueryItem(name: "arrCityCode", value: journey.arrivalCode),
            URLQueryItem(name: "depDate", value: dayFormatter.string(from: journey.date))
        ]
        return components?.url
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

    private static let airportCodes: [(alias: String, code: String)] = [
        ("苏南硕放", "WUX"), ("上海虹桥", "SHA"), ("上海浦东", "SHA"),
        ("北京大兴", "BJS"), ("北京首都", "BJS"), ("成都天府", "CTU"), ("成都双流", "CTU"),
        ("西双版纳", "JHG"), ("香格里拉", "DIG"), ("乌鲁木齐", "URC"), ("张家界", "DYG"),
        ("石家庄", "SJW"), ("哈尔滨", "HRB"), ("呼和浩特", "HET"), ("景德镇", "JDZ"),
        ("苏州", "WUX"), ("无锡", "WUX"), ("宁波", "NGB"), ("栎社", "NGB"),
        ("天津", "TSN"), ("滨海", "TSN"), ("上海", "SHA"), ("虹桥", "SHA"), ("浦东", "SHA"),
        ("北京", "BJS"), ("首都", "BJS"), ("大兴", "BJS"), ("广州", "CAN"), ("白云", "CAN"),
        ("深圳", "SZX"), ("宝安", "SZX"), ("成都", "CTU"), ("双流", "CTU"), ("天府", "CTU"),
        ("杭州", "HGH"), ("萧山", "HGH"), ("南京", "NKG"), ("禄口", "NKG"),
        ("武汉", "WUH"), ("天河", "WUH"), ("西安", "SIA"), ("咸阳", "SIA"),
        ("长沙", "CSX"), ("黄花", "CSX"), ("厦门", "XMN"), ("高崎", "XMN"), ("翔安", "XMN"),
        ("三亚", "SYX"), ("凤凰", "SYX"), ("海口", "HAK"), ("美兰", "HAK"),
        ("昆明", "KMG"), ("长水", "KMG"), ("重庆", "CKG"), ("江北", "CKG"),
        ("青岛", "TAO"), ("胶东", "TAO"), ("郑州", "CGO"), ("新郑", "CGO"),
        ("济南", "TNA"), ("遥墙", "TNA"), ("沈阳", "SHE"), ("桃仙", "SHE"),
        ("大连", "DLC"), ("周水子", "DLC"), ("长春", "CGQ"), ("龙嘉", "CGQ"),
        ("太原", "TYN"), ("武宿", "TYN"), ("南昌", "KHN"), ("昌北", "KHN"),
        ("合肥", "HFE"), ("新桥", "HFE"), ("贵阳", "KWE"), ("龙洞堡", "KWE"),
        ("南宁", "NNG"), ("吴圩", "NNG"), ("兰州", "LHW"), ("中川", "LHW"),
        ("拉萨", "LXA"), ("贡嘎", "LXA"), ("珠海", "ZUH"), ("金湾", "ZUH"),
        ("福州", "FOC"), ("泉州", "JJN"), ("温州", "WNZ"), ("烟台", "YNT"),
        ("徐州", "XUZ"), ("南通", "NTG"), ("扬州", "YTY"), ("惠州", "HUZ"),
        ("揭阳", "SWA"), ("佛山", "FUO"), ("桂林", "KWL"), ("丽江", "LJG"),
        ("大理", "DLU"), ("腾冲", "TCZ"), ("银川", "INC"), ("西宁", "XNN"),
        ("喀什", "KHG"), ("香港", "HKG"), ("澳门", "MFM"), ("台北", "TPE")
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
enum FliggyMTOPFlightPage {
    private static let appKey = "12574478"
    private static let apiName = "mtop.trip.flight.flightSearch"

    static func search(
        departureCode: String,
        arrivalCode: String,
        date: Date,
        session: URLSession = .shared
    ) async throws -> FliggyFlightSearchResult {
        let payloadObject: [String: Any] = [
            "searchType": 1,
            "depCityCode": departureCode,
            "arrCityCode": arrivalCode,
            "leaveDate": dayFormatter.string(from: date),
            "itineraryFilter": "0",
            "leaveCabinClass": "0",
            "useAcrossAgent": 1
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        guard let payload = String(data: payloadData, encoding: .utf8) else {
            throw FliggyFlightDirectError.invalidResponse
        }

        var cookies: [String: HTTPCookie] = [:]
        var lastProviderMessage = "没有返回可用航班"
        for attempt in 0..<3 {
            guard !Task.isCancelled else { throw CancellationError() }
            let token = cookies["_m_h5_tk"]?.value.split(separator: "_").first.map(String.init) ?? ""
            let timestamp = String(Int64(Date.now.timeIntervalSince1970 * 1_000))
            let signature = md5("\(token)&\(timestamp)&\(appKey)&\(payload)")
            guard let url = requestURL(timestamp: timestamp, signature: signature, payload: payload) else {
                throw FliggyFlightDirectError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.setValue("AnyTravel/0.7 iOS URLSession", forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://h5.m.taobao.com/trip/flight/search/index.html", forHTTPHeaderField: "Referer")
            request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
            if !cookies.isEmpty {
                request.setValue(
                    cookies.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                    forHTTPHeaderField: "Cookie"
                )
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FliggyFlightDirectError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else {
                throw FliggyFlightDirectError.invalidResponse
            }
            guard http.statusCode == 200 else { throw FliggyFlightDirectError.httpFailure(http.statusCode) }
            responseCookies(http, for: url).forEach { cookies[$0.name] = $0 }

            if let parsed = parse(data: data) { return parsed }
            lastProviderMessage = providerMessage(in: data) ?? lastProviderMessage
            if attempt < 2 { try await Task.sleep(for: .milliseconds(450)) }
        }
        throw FliggyFlightDirectError.providerRejected(lastProviderMessage)
    }

    static func parse(data: Data) -> FliggyFlightSearchResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              String(describing: root["ret"] ?? "").contains("SUCCESS"),
              let content = root["data"] as? [String: Any],
              boolValue(content["success"]) else { return nil }

        var offers: [FliggyFlightOffer] = []
        let allowedTypes: Set<String> = ["DIRECT", "TRANSFER", "TRANSFER_RECOMMEND", "STOP"]
        for group in content["items"] as? [[String: Any]] ?? [] {
            guard allowedTypes.contains(stringValue(group["itemType"])) else { continue }
            for row in group["itemDatas"] as? [[String: Any]] ?? [] {
                guard let price = integerValue(row["bestPrice"]), price > 0,
                      let departure = clock(from: stringValue(row["depTime"] ?? row["depTimeShow"])),
                      let arrival = clock(from: stringValue(row["arrTime"] ?? row["arrTimeShow"])) else { continue }
                offers.append(
                    FliggyFlightOffer(
                        price: price,
                        airline: stringValue(row["airlineChineseName"] ?? row["airlineChineseShortName"]),
                        flightNumber: stringValue(row["flightName"]),
                        departureTime: departure,
                        arrivalTime: arrival,
                        departureAirport: airportName(row, prefix: "dep"),
                        arrivalAirport: airportName(row, prefix: "arr"),
                        durationMinutes: integerValue(row["duration"] ?? row["flyTime"] ?? row["durationMinutes"])
                    )
                )
            }
        }
        var seen: Set<String> = []
        offers = offers.filter {
            seen.insert("\($0.flightNumber)|\($0.departureTime)|\($0.price)").inserted
        }
        .sorted {
            if $0.price != $1.price { return $0.price < $1.price }
            return $0.departureTime < $1.departureTime
        }
        let lowest = integerValue(content["lowestPrice"]) ?? offers.map(\.price).min()
        guard !offers.isEmpty || lowest != nil else { return nil }
        return FliggyFlightSearchResult(offers: offers, lowestPrice: lowest)
    }

    private static func requestURL(timestamp: String, signature: String, payload: String) -> URL? {
        var components = URLComponents(string: "https://h5api.m.taobao.com/h5/\(apiName)/1.0/")
        components?.queryItems = [
            URLQueryItem(name: "jsv", value: "2.7.0"),
            URLQueryItem(name: "appKey", value: appKey),
            URLQueryItem(name: "t", value: timestamp),
            URLQueryItem(name: "sign", value: signature),
            URLQueryItem(name: "api", value: apiName),
            URLQueryItem(name: "v", value: "1.0"),
            URLQueryItem(name: "type", value: "originaljson"),
            URLQueryItem(name: "dataType", value: "json"),
            URLQueryItem(name: "data", value: payload)
        ]
        return components?.url
    }

    private static func responseCookies(_ response: HTTPURLResponse, for url: URL) -> [HTTPCookie] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
    }

    private static func providerMessage(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let messages = root["ret"] as? [String] { return messages.joined(separator: "，") }
        return stringValue(root["ret"]).nonEmpty
    }

    private static func airportName(_ row: [String: Any], prefix: String) -> String {
        let base = stringValue(
            row["\(prefix)AirportName"]
                ?? row["\(prefix)AirportShortName"]
                ?? row["\(prefix)AirportShow"]
                ?? row["\(prefix)AirportCode"]
        )
        let terminal = stringValue(row["\(prefix)AirportTerm"] ?? row["\(prefix)Terminal"])
        if terminal.isEmpty || base.contains(terminal) { return base }
        return "\(base) \(terminal)"
    }

    private static func clock(from value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)([0-2]?\d:[0-5]\d)(?:$|\s)"#),
              let match = regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).last,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        let pieces = value[range].split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), hour <= 23 else { return nil }
        return String(format: "%02d:%@", hour, String(pieces[1]))
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let number = Double(value) { return Int(number.rounded()) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["true", "1"].contains(value.lowercased()) }
        return false
    }

    private static func stringValue(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
