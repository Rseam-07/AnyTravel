import Foundation

enum Railway12306DirectError: LocalizedError, Equatable {
    case missingDates
    case invalidResponse
    case httpFailure(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingDates:
            "先添上出发日期，才能读取铁路票价。"
        case .invalidResponse:
            "铁路 12306 返回了无法识别的数据。"
        case let .httpFailure(status):
            "铁路 12306 暂时拒绝了查询（\(status)）。"
        case let .network(message):
            "铁路票价暂时没有抵达：\(message)"
        }
    }
}

struct Railway12306DirectClient {
    private struct Station: Hashable, Sendable {
        var name: String
        var code: String
        var city: String
    }

    private struct Journey: Sendable {
        var direction: TransportDirection
        var date: Date
        var from: Station
        var to: Station
    }

    private struct Train: Sendable {
        var trainNumber: String
        var serviceNumber: String
        var originCode: String
        var destinationCode: String
        var originName: String
        var destinationName: String
        var departureTime: String
        var arrivalTime: String
        var durationMinutes: Int?
        var fromStationNumber: String
        var toStationNumber: String
        var seatTypes: String
        var availability: [String: String]
    }

    private struct Fare: Sendable {
        var amountCNY: Int
        var name: String
    }

    private let session: URLSession
    private let stationURL: URL
    private let baseURL: URL
    private let resultLimit: Int

    init(
        session: URLSession = .shared,
        stationURL: URL = URL(string: "https://kyfw.12306.cn/otn/resources/js/framework/station_name.js")!,
        baseURL: URL = URL(string: "https://kyfw.12306.cn/otn")!,
        resultLimit: Int = 8
    ) {
        self.session = session
        self.stationURL = stationURL
        self.baseURL = baseURL
        self.resultLimit = min(max(resultLimit, 1), 12)
    }

    func enrichTransportOptions(
        _ currentOptions: [TransportOption],
        origin: String,
        destination: String,
        logistics: TripLogistics,
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?
    ) async throws -> PricingEnrichmentResult<[TransportOption]> {
        guard let departureDate = logistics.startDate else { throw Railway12306DirectError.missingDates }
        let capturedAt = Date.now
        let stationSource = try await load(stationURL, referer: baseURL.appendingPathComponent("leftTicket/init"))
        guard let stationText = String(data: stationSource, encoding: .utf8) else {
            throw Railway12306DirectError.invalidResponse
        }
        let stations = Self.parseStations(stationText)
        guard let from = Self.findStation(origin, in: stations),
              let to = Self.findStation(destination, in: stations) else {
            return PricingEnrichmentResult(
                value: currentOptions,
                receivedCount: 0,
                capturedAt: capturedAt,
                isCached: false,
                issues: [
                    PricingProviderIssue(
                        provider: "12306",
                        status: "station_not_found",
                        detail: "\(origin) → \(destination)"
                    )
                ]
            )
        }

        var journeys = [Journey(direction: .outbound, date: departureDate, from: from, to: to)]
        if let returnDate = logistics.endDate {
            journeys.append(Journey(direction: .returnTrip, date: returnDate, from: to, to: from))
        }

        var liveOptions: [TransportOption] = []
        var issues: [PricingProviderIssue] = []
        for journey in journeys {
            do {
                let options = try await search(
                    journey,
                    currentOptions: currentOptions,
                    accessPoints: accessPoints,
                    accommodation: accommodation,
                    capturedAt: capturedAt
                )
                liveOptions.append(contentsOf: options)
                if options.isEmpty {
                    issues.append(
                        PricingProviderIssue(
                            provider: "12306",
                            status: "no_matching_quotes",
                            detail: "\(journey.direction.title)暂无可售班次"
                        )
                    )
                }
            } catch {
                issues.append(
                    PricingProviderIssue(
                        provider: "12306",
                        status: "failed",
                        detail: "\(journey.direction.title)查询失败：\(error.localizedDescription)"
                    )
                )
            }
        }

        guard !liveOptions.isEmpty else {
            return PricingEnrichmentResult(
                value: currentOptions,
                receivedCount: 0,
                capturedAt: capturedAt,
                isCached: false,
                issues: issues
            )
        }

        let preferredMode = logistics.preferredLongDistanceMode
        var recommendedDirections: Set<TransportDirection> = []
        for index in liveOptions.indices {
            let direction = liveOptions[index].journeyDirection
            let matchesPreference = preferredMode == nil || preferredMode == .train
            liveOptions[index].isRecommended = matchesPreference && !recommendedDirections.contains(direction)
            if liveOptions[index].isRecommended { recommendedDirections.insert(direction) }
        }

        let refreshedDirections = Set(liveOptions.map(\.journeyDirection))
        let merged = (liveOptions + currentOptions.filter {
            $0.mode != .train || !refreshedDirections.contains($0.journeyDirection)
        }).sorted(by: Self.compareOptions)
        let quotedCount = liveOptions.flatMap(\.quotes).filter { $0.amountCNY != nil }.count
        return PricingEnrichmentResult(
            value: merged,
            receivedCount: quotedCount,
            capturedAt: capturedAt,
            isCached: false,
            issues: issues
        )
    }

    private func search(
        _ journey: Journey,
        currentOptions: [TransportOption],
        accessPoints: [AccessPoint],
        accommodation: AccommodationOption?,
        capturedAt: Date
    ) async throws -> [TransportOption] {
        let day = Self.dayFormatter.string(from: journey.date)
        let bookingURL = Self.bookingURL(baseURL: baseURL, journey: journey, day: day)
        _ = try await load(bookingURL, referer: baseURL.appendingPathComponent("leftTicket/init"))

        var query = URLComponents(
            url: baseURL.appendingPathComponent("leftTicket/query"),
            resolvingAgainstBaseURL: false
        )!
        query.queryItems = [
            URLQueryItem(name: "leftTicketDTO.train_date", value: day),
            URLQueryItem(name: "leftTicketDTO.from_station", value: journey.from.code),
            URLQueryItem(name: "leftTicketDTO.to_station", value: journey.to.code),
            URLQueryItem(name: "purpose_codes", value: "ADULT")
        ]
        guard let queryURL = query.url else { throw Railway12306DirectError.invalidResponse }
        let queryData = try await load(queryURL, referer: bookingURL)
        let trains = try Self.parseTrainQuery(queryData)
            .sorted(by: Self.compareTrains)
            .prefix(resultLimit)

        var results: [TransportOption] = []
        for train in trains {
            let fare = try? await loadFare(for: train, date: day, referer: bookingURL)
            let localStationName = journey.direction == .returnTrip ? train.originName : train.destinationName
            let fallbackPoint = currentOptions.first {
                $0.mode == .train && $0.journeyDirection == journey.direction
            }?.arrivalAccessPoint
            let accessPoint = Self.bestAccessPoint(
                named: localStationName,
                accessPoints: accessPoints,
                fallback: fallbackPoint
            )
            let transferMeters = accessPoint.flatMap { point in
                accommodation.map { LogisticsSearchService.distance(from: point.coordinate, to: $0.coordinate) }
            }
            let departure = Self.date(day: day, time: train.departureTime)
            let arrival = Self.arrivalDate(day: day, departure: train.departureTime, arrival: train.arrivalTime)
            let availability = Self.availabilitySummary(train.availability)
            let quote = ProviderQuote(
                provider: .railway12306,
                amountCNY: fare?.amountCNY,
                unit: .perPerson,
                kind: fare == nil ? .checkOnProvider : .live,
                capturedAt: capturedAt,
                bookingURL: bookingURL,
                note: fare == nil
                    ? "余票来自铁路 12306；票价请在购票页复核"
                    : "\(fare?.name ?? "席位") · 铁路 12306 当前公开查询价，提交前请复核",
                sourceLabel: "铁路 12306",
                availability: availability
            )
            var reasons = ["\(train.departureTime)–\(train.arrivalTime) · \(availability)"]
            if let transferMeters, let accessPoint {
                reasons.append(
                    journey.direction == .returnTrip
                        ? "住宿到\(accessPoint.name)约\(transferMeters.anyTravelDistanceText)"
                        : "\(accessPoint.name)到住宿约\(transferMeters.anyTravelDistanceText)"
                )
            }
            results.append(
                TransportOption(
                    mode: .train,
                    title: "\(train.serviceNumber) · \(train.originName)→\(train.destinationName)",
                    originName: train.originName,
                    destinationName: train.destinationName,
                    direction: journey.direction,
                    durationMinutes: train.durationMinutes,
                    departureTime: departure,
                    arrivalTime: arrival,
                    arrivalAccessPoint: accessPoint,
                    hotelTransferMeters: transferMeters,
                    quotes: [quote],
                    recommendationReasons: reasons,
                    isRecommended: false
                )
            )
        }
        return results
    }

    private func loadFare(for train: Train, date: String, referer: URL) async throws -> Fare? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("leftTicket/queryTicketPrice"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "train_no", value: train.trainNumber),
            URLQueryItem(name: "from_station_no", value: train.fromStationNumber),
            URLQueryItem(name: "to_station_no", value: train.toStationNumber),
            URLQueryItem(name: "seat_types", value: train.seatTypes),
            URLQueryItem(name: "train_date", value: date)
        ]
        guard let url = components.url else { throw Railway12306DirectError.invalidResponse }
        let data = try await load(url, referer: referer)
        return try Self.parseFare(data)
    }

    private func load(_ url: URL, referer: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Railway12306DirectError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw Railway12306DirectError.httpFailure(http.statusCode)
            }
            return data
        } catch let error as Railway12306DirectError {
            throw error
        } catch {
            throw Railway12306DirectError.network(error.localizedDescription)
        }
    }

    private static func parseFare(_ data: Data) throws -> Fare? {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["status"] as? Bool != false,
              let values = payload["data"] as? [String: Any] else {
            throw Railway12306DirectError.invalidResponse
        }
        let priorities = [
            ("O", "二等座"), ("M", "一等座"), ("A3", "硬座"), ("A4", "软座"),
            ("A1", "硬卧"), ("A2", "软卧"), ("9", "商务座")
        ]
        for (key, name) in priorities {
            if let amount = yuanAmount(values[key]) { return Fare(amountCNY: amount, name: name) }
        }
        for (key, value) in values {
            if let amount = yuanAmount(value) { return Fare(amountCNY: amount, name: key) }
        }
        return nil
    }

    private static func parseStations(_ source: String) -> [Station] {
        source.split(separator: "@", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 8, !fields[1].isEmpty, !fields[2].isEmpty else { return nil }
            return Station(name: fields[1], code: fields[2], city: fields[7].isEmpty ? fields[1] : fields[7])
        }
    }

    private static func findStation(_ query: String, in stations: [Station]) -> Station? {
        let term = normalizedStationName(query)
        return stations.first { normalizedStationName($0.name) == term }
            ?? stations.first { normalizedStationName($0.city) == term }
            ?? stations.first {
                normalizedStationName($0.name).contains(term) || term.contains(normalizedStationName($0.name))
            }
    }

    private static func parseTrainQuery(_ data: Data) throws -> [Train] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["status"] as? Bool != false,
              let queryData = payload["data"] as? [String: Any],
              let rows = queryData["result"] as? [String] else {
            throw Railway12306DirectError.invalidResponse
        }
        let stationMap = queryData["map"] as? [String: String] ?? [:]
        return rows.compactMap { row in
            let fields = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count > 35, fields[11] == "Y", !fields[2].isEmpty, !fields[3].isEmpty else { return nil }
            return Train(
                trainNumber: fields[2],
                serviceNumber: fields[3],
                originCode: fields[6],
                destinationCode: fields[7],
                originName: stationMap[fields[6]] ?? fields[6],
                destinationName: stationMap[fields[7]] ?? fields[7],
                departureTime: fields[8],
                arrivalTime: fields[9],
                durationMinutes: durationMinutes(fields[10]),
                fromStationNumber: fields[16],
                toStationNumber: fields[17],
                seatTypes: fields[35],
                availability: [
                    "business": fields[32], "firstClass": fields[31], "secondClass": fields[30],
                    "softSleeper": fields[23], "hardSleeper": fields[28], "hardSeat": fields[29],
                    "noSeat": fields[26]
                ]
            )
        }
    }

    private static func yuanAmount(_ value: Any?) -> Int? {
        guard let text = value as? String,
              let range = text.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
              let amount = Double(text[range]), amount > 0 else { return nil }
        return Int(amount.rounded())
    }

    private static func durationMinutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func availabilitySummary(_ values: [String: String]) -> String {
        let seats = [
            ("secondClass", "二等座"), ("firstClass", "一等座"), ("business", "商务座"),
            ("hardSleeper", "硬卧"), ("softSleeper", "软卧"), ("hardSeat", "硬座"), ("noSeat", "无座")
        ]
        let available = seats.compactMap { key, name -> String? in
            guard let value = values[key], value == "有" || (Int(value) ?? 0) > 0 else { return nil }
            return "\(name)\(value == "有" ? "有票" : value)"
        }.prefix(3)
        return available.isEmpty ? "余票以 12306 页面为准" : available.joined(separator: " · ")
    }

    private static func compareTrains(_ lhs: Train, _ rhs: Train) -> Bool {
        let lhsPrefix = lhs.serviceNumber.first.map { "GDC".contains($0) } == true ? 0 : 1
        let rhsPrefix = rhs.serviceNumber.first.map { "GDC".contains($0) } == true ? 0 : 1
        let lhsDaytime = ("06:00"..."20:30").contains(lhs.departureTime) ? 0 : 1
        let rhsDaytime = ("06:00"..."20:30").contains(rhs.departureTime) ? 0 : 1
        if lhsPrefix != rhsPrefix { return lhsPrefix < rhsPrefix }
        if lhsDaytime != rhsDaytime { return lhsDaytime < rhsDaytime }
        if lhs.durationMinutes != rhs.durationMinutes { return (lhs.durationMinutes ?? .max) < (rhs.durationMinutes ?? .max) }
        return lhs.departureTime < rhs.departureTime
    }

    private static func compareOptions(_ lhs: TransportOption, _ rhs: TransportOption) -> Bool {
        if lhs.journeyDirection != rhs.journeyDirection { return lhs.journeyDirection == .outbound }
        if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
        let lhsAmount = lhs.quotes.compactMap(\.amountCNY).min() ?? .max
        let rhsAmount = rhs.quotes.compactMap(\.amountCNY).min() ?? .max
        if lhsAmount != rhsAmount { return lhsAmount < rhsAmount }
        return (lhs.durationMinutes ?? .max) < (rhs.durationMinutes ?? .max)
    }

    private static func bestAccessPoint(named name: String, accessPoints: [AccessPoint], fallback: AccessPoint?) -> AccessPoint? {
        let rails = accessPoints.filter { $0.kind == .rail }
        let target = normalizedStationName(name)
        if let exact = rails.first(where: { normalizedStationName($0.name) == target }) { return exact }
        if let close = rails.first(where: {
            normalizedStationName($0.name).contains(target) || target.contains(normalizedStationName($0.name))
        }) { return close }
        return fallback ?? rails.first
    }

    private static func normalizedStationName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "特别行政区", with: "")
            .replacingOccurrences(of: "自治区", with: "")
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "市", with: "")
            .replacingOccurrences(of: "站", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func bookingURL(baseURL: URL, journey: Journey, day: String) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("leftTicket/init"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "linktypeid", value: "dc"),
            URLQueryItem(name: "fs", value: "\(journey.from.name),\(journey.from.code)"),
            URLQueryItem(name: "ts", value: "\(journey.to.name),\(journey.to.code)"),
            URLQueryItem(name: "date", value: day),
            URLQueryItem(name: "flag", value: "N,N,Y")
        ]
        return components.url!
    }

    private static func date(day: String, time: String) -> Date? {
        dateTimeFormatter.date(from: "\(day) \(time)")
    }

    private static func arrivalDate(day: String, departure: String, arrival: String) -> Date? {
        guard let departureDate = date(day: day, time: departure),
              var arrivalDate = date(day: day, time: arrival) else { return nil }
        if arrivalDate < departureDate {
            arrivalDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate
        }
        return arrivalDate
    }

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
