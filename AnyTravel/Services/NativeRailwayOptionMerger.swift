import Foundation

enum NativeRailwayOptionMerger {
    static func merging(_ incoming: [TransportOption], into current: [TransportOption]) -> [TransportOption] {
        guard !incoming.isEmpty else { return current }
        let refreshedDirections = Set(incoming.filter(hasCurrentPrice).map(\.journeyDirection))
        var output = current.filter { option in
            guard option.mode == .train, refreshedDirections.contains(option.journeyDirection) else { return true }
            return hasCurrentPrice(option)
        }

        for candidate in incoming {
            if let index = output.firstIndex(where: { matches($0, candidate) }) {
                output[index].quotes = mergeQuotes(output[index].quotes, candidate.quotes)
                output[index].recommendationReasons = unique(
                    output[index].recommendationReasons + candidate.recommendationReasons
                )
                output[index].durationMinutes = candidate.durationMinutes ?? output[index].durationMinutes
                output[index].departureTime = candidate.departureTime ?? output[index].departureTime
                output[index].arrivalTime = candidate.arrivalTime ?? output[index].arrivalTime
                output[index].arrivalAccessPoint = candidate.arrivalAccessPoint ?? output[index].arrivalAccessPoint
                output[index].hotelTransferMeters = candidate.hotelTransferMeters ?? output[index].hotelTransferMeters
                output[index].title = candidate.title
                output[index].originName = candidate.originName
                output[index].destinationName = candidate.destinationName
            } else {
                output.append(candidate)
            }
        }
        return output.sorted(by: compare)
    }

    private static func hasCurrentPrice(_ option: TransportOption) -> Bool {
        option.quotes.contains(where: \.isCurrentPrice)
    }

    private static func matches(_ lhs: TransportOption, _ rhs: TransportOption) -> Bool {
        guard lhs.mode == .train,
              rhs.mode == .train,
              lhs.journeyDirection == rhs.journeyDirection else { return false }
        let lhsNumber = serviceNumber(in: lhs.title)
        let rhsNumber = serviceNumber(in: rhs.title)
        if let lhsNumber, let rhsNumber { return lhsNumber == rhsNumber }
        guard let lhsDeparture = lhs.departureTime, let rhsDeparture = rhs.departureTime else { return false }
        return abs(lhsDeparture.timeIntervalSince(rhsDeparture)) <= 2 * 60
    }

    private static func serviceNumber(in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b[A-Z]\d{1,5}\b"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return nil }
        return String(value[range]).uppercased()
    }

    private static func mergeQuotes(_ existing: [ProviderQuote], _ incoming: [ProviderQuote]) -> [ProviderQuote] {
        var output = existing
        for quote in incoming {
            if let index = output.firstIndex(where: { $0.provider == quote.provider && $0.unit == quote.unit }) {
                let old = output[index]
                if old.amountCNY == nil || (quote.amountCNY != nil && (quote.capturedAt ?? .distantPast) >= (old.capturedAt ?? .distantPast)) {
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

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func compare(_ lhs: TransportOption, _ rhs: TransportOption) -> Bool {
        if lhs.journeyDirection != rhs.journeyDirection { return lhs.journeyDirection == .outbound }
        if hasCurrentPrice(lhs) != hasCurrentPrice(rhs) { return hasCurrentPrice(lhs) }
        if lhs.mode != rhs.mode { return lhs.mode.rawValue < rhs.mode.rawValue }
        let lhsPrice = lhs.quotes.filter(\.isCurrentPrice).compactMap(\.amountCNY).min() ?? .max
        let rhsPrice = rhs.quotes.filter(\.isCurrentPrice).compactMap(\.amountCNY).min() ?? .max
        if lhsPrice != rhsPrice { return lhsPrice < rhsPrice }
        if lhs.departureTime != rhs.departureTime {
            return (lhs.departureTime ?? .distantFuture) < (rhs.departureTime ?? .distantFuture)
        }
        return lhs.title < rhs.title
    }
}
