import Foundation

enum NativeFlightOptionMerger {
    static func merging(
        _ incoming: [TransportOption],
        into current: [TransportOption],
        provider: TravelProvider,
        direction: TransportDirection
    ) -> [TransportOption] {
        var output = current

        for index in output.indices where output[index].mode == .flight && output[index].journeyDirection == direction {
            output[index].quotes.removeAll { $0.provider == provider }
        }
        if incoming.contains(where: hasCurrentPrice) {
            output.removeAll { option in
                option.mode == .flight
                    && option.journeyDirection == direction
                    && !hasCurrentPrice(option)
            }
        }

        for candidate in incoming {
            if let index = output.firstIndex(where: { matches($0, candidate) }) {
                output[index].quotes = mergingQuotes(output[index].quotes, candidate.quotes)
                output[index].recommendationReasons = unique(
                    output[index].recommendationReasons + candidate.recommendationReasons
                )
                output[index].durationMinutes = output[index].durationMinutes ?? candidate.durationMinutes
                output[index].departureTime = output[index].departureTime ?? candidate.departureTime
                output[index].arrivalTime = output[index].arrivalTime ?? candidate.arrivalTime
                output[index].arrivalAccessPoint = output[index].arrivalAccessPoint ?? candidate.arrivalAccessPoint
                output[index].hotelTransferMeters = output[index].hotelTransferMeters ?? candidate.hotelTransferMeters
                if output[index].title.hasPrefix("航班抵达") || output[index].title.hasPrefix("去哪儿 ·") {
                    output[index].title = candidate.title
                    output[index].originName = candidate.originName
                    output[index].destinationName = candidate.destinationName
                }
            } else {
                output.append(candidate)
            }
        }

        output.removeAll { option in
            option.mode == .flight
                && option.journeyDirection == direction
                && option.quotes.isEmpty
                && incoming.contains(where: { matches($0, option) })
        }
        return output.sorted(by: compare)
    }

    private static func hasCurrentPrice(_ option: TransportOption) -> Bool {
        option.quotes.contains(where: \.isCurrentPrice)
    }

    private static func matches(_ lhs: TransportOption, _ rhs: TransportOption) -> Bool {
        guard lhs.mode == .flight,
              rhs.mode == .flight,
              lhs.journeyDirection == rhs.journeyDirection else { return false }

        let lhsCode = flightNumber(in: lhs.title)
        let rhsCode = flightNumber(in: rhs.title)
        if let lhsCode, let rhsCode, lhsCode == rhsCode { return true }

        guard let lhsDeparture = lhs.departureTime,
              let rhsDeparture = rhs.departureTime,
              abs(lhsDeparture.timeIntervalSince(rhsDeparture)) <= 5 * 60 else { return false }
        if let lhsArrival = lhs.arrivalTime, let rhsArrival = rhs.arrivalTime,
           abs(lhsArrival.timeIntervalSince(rhsArrival)) > 10 * 60 {
            return false
        }
        let lhsOrigin = normalizedPlace(lhs.originName)
        let rhsOrigin = normalizedPlace(rhs.originName)
        let lhsDestination = normalizedPlace(lhs.destinationName)
        let rhsDestination = normalizedPlace(rhs.destinationName)
        return compatible(lhsOrigin, rhsOrigin) && compatible(lhsDestination, rhsDestination)
    }

    private static func mergingQuotes(_ lhs: [ProviderQuote], _ rhs: [ProviderQuote]) -> [ProviderQuote] {
        var output = lhs
        for quote in rhs {
            if let index = output.firstIndex(where: { $0.provider == quote.provider && $0.unit == quote.unit }) {
                let existing = output[index]
                if existing.amountCNY == nil
                    || quote.amountCNY != nil && (quote.capturedAt ?? .distantPast) >= (existing.capturedAt ?? .distantPast) {
                    output[index] = quote
                }
            } else {
                output.append(quote)
            }
        }
        return output.sorted {
            if $0.isCurrentPrice != $1.isCurrentPrice { return $0.isCurrentPrice }
            if ($0.amountCNY != nil) != ($1.amountCNY != nil) { return $0.amountCNY != nil }
            return ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max)
        }
    }

    private static func flightNumber(in value: String) -> String? {
        let pattern = #"(?i)\b[A-Z0-9]{2}\s?\d{3,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return nil }
        return value[range].replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func normalizedPlace(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "国际机场", with: "")
            .replacingOccurrences(of: "机场", with: "")
            .replacingOccurrences(of: "航站楼", with: "")
            .replacingOccurrences(of: #"T\d+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func compatible(_ lhs: String, _ rhs: String) -> Bool {
        lhs.isEmpty || rhs.isEmpty || lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func compare(_ lhs: TransportOption, _ rhs: TransportOption) -> Bool {
        if lhs.journeyDirection != rhs.journeyDirection { return lhs.journeyDirection == .outbound }
        if hasCurrentPrice(lhs) != hasCurrentPrice(rhs) { return hasCurrentPrice(lhs) }
        if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
        if lhs.mode != rhs.mode { return lhs.mode.rawValue < rhs.mode.rawValue }
        let lhsDurationRank = durationRank(lhs.durationMinutes)
        let rhsDurationRank = durationRank(rhs.durationMinutes)
        if lhsDurationRank != rhsDurationRank { return lhsDurationRank < rhsDurationRank }
        let lhsPrice = lhs.quotes.filter(\.isCurrentPrice).compactMap(\.amountCNY).min() ?? .max
        let rhsPrice = rhs.quotes.filter(\.isCurrentPrice).compactMap(\.amountCNY).min() ?? .max
        if lhsPrice != rhsPrice { return lhsPrice < rhsPrice }
        if lhs.departureTime != rhs.departureTime {
            return (lhs.departureTime ?? .distantFuture) < (rhs.departureTime ?? .distantFuture)
        }
        return lhs.title < rhs.title
    }

    private static func durationRank(_ durationMinutes: Int?) -> Int {
        guard let durationMinutes else { return 1 }
        return (30...(16 * 60)).contains(durationMinutes) ? 0 : 2
    }
}
