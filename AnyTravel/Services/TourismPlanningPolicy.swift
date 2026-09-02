import CoreLocation
import Foundation

/// Shared timing assumptions used by route ordering, the visible timeline and
/// pacing diagnostics. These are planning estimates, not claims about a venue's
/// actual opening hours.
struct TourismPlanningPolicy {
    struct OpeningWindow: Equatable, Sendable {
        let startMinute: Int
        let endMinute: Int
    }

    struct DayRhythm: Equatable, Sendable {
        let startMinute: Int
        let daytimeEndMinute: Int
        let nightEndMinute: Int
        let lunchStartMinute: Int
        let lunchDurationMinutes: Int
        let nightStartMinute: Int
        let transferBufferMinutes: Int
        let contingencyRatio: Double
    }

    func rhythm(for pace: TripPace) -> DayRhythm {
        switch pace {
        case .relaxed:
            DayRhythm(
                startMinute: 10 * 60,
                daytimeEndMinute: 17 * 60 + 30,
                nightEndMinute: 21 * 60,
                lunchStartMinute: 12 * 60,
                lunchDurationMinutes: 90,
                nightStartMinute: 18 * 60 + 30,
                transferBufferMinutes: 10,
                contingencyRatio: 0.20
            )
        case .balanced:
            DayRhythm(
                startMinute: 9 * 60 + 30,
                daytimeEndMinute: 18 * 60 + 30,
                nightEndMinute: 21 * 60 + 30,
                lunchStartMinute: 12 * 60,
                lunchDurationMinutes: 75,
                nightStartMinute: 18 * 60 + 30,
                transferBufferMinutes: 8,
                contingencyRatio: 0.15
            )
        case .full:
            DayRhythm(
                startMinute: 9 * 60,
                daytimeEndMinute: 20 * 60,
                nightEndMinute: 22 * 60,
                lunchStartMinute: 12 * 60 + 15,
                lunchDurationMinutes: 60,
                nightStartMinute: 18 * 60 + 30,
                transferBufferMinutes: 6,
                contingencyRatio: 0.10
            )
        }
    }

    func visitMinutes(for place: TravelPlace, pace: TripPace) -> Int {
        let base: Int = switch place.interest {
        case .gardens: 105
        case .culture: 120
        case .food: 75
        case .nature: 120
        case .family: 150
        case .night: 100
        }
        let multiplier: Double = switch pace {
        case .relaxed: 1.12
        case .balanced: 1
        case .full: 0.86
        }
        let primaryMultiplier = place.planningPriority == .primary ? 1.28 : 1
        return roundedToFive(Int((Double(base) * multiplier * primaryMultiplier).rounded()))
    }

    func estimatedTravelMinutes(
        from source: Coordinate,
        to destination: Coordinate,
        mode: TravelMode
    ) -> Int {
        let kilometers = distanceMeters(from: source, to: destination) / 1_000
        let speedAndOverhead: (kilometersPerHour: Double, overhead: Double) = switch mode {
        case .walking: (4.5, 4)
        case .transit: (18, 12)
        case .driving: (27, 9)
        }
        let raw = kilometers / speedAndOverhead.kilometersPerHour * 60 + speedAndOverhead.overhead
        return min(max(roundedToFive(Int(raw.rounded())), 5), 120)
    }

    func estimatedTravelMinutes(for day: ItineraryDay, mode: TravelMode) -> Int {
        guard day.stops.count > 1 else { return 0 }
        return zip(day.stops, day.stops.dropFirst()).reduce(0) { total, pair in
            total + estimatedTravelMinutes(
                from: pair.0.coordinate,
                to: pair.1.coordinate,
                mode: mode
            )
        }
    }

    func estimatedDayMinutes(
        for day: ItineraryDay,
        pace: TripPace,
        mode: TravelMode,
        actualTravelMinutes: Int? = nil
    ) -> Int {
        let visits = day.stops.reduce(0) { $0 + visitMinutes(for: $1, pace: pace) }
        let travel = actualTravelMinutes ?? estimatedTravelMinutes(for: day, mode: mode)
        let meal = day.stops.contains(where: { $0.interest == .food })
            ? 0
            : rhythm(for: pace).lunchDurationMinutes
        let buffer = Int((Double(visits + travel) * rhythm(for: pace).contingencyRatio).rounded())
        return visits + travel + meal + buffer
    }

    func availableDayMinutes(
        for day: ItineraryDay,
        pace: TripPace,
        constraints: TourismDayConstraints = .none
    ) -> Int {
        let rhythm = rhythm(for: pace)
        let ordinaryEnd = day.stops.contains(where: { $0.interest == .night })
            ? rhythm.nightEndMinute
            : rhythm.daytimeEndMinute
        let start = max(rhythm.startMinute, constraints.earliestStartMinute ?? rhythm.startMinute)
        let end = min(ordinaryEnd, constraints.latestEndMinute ?? ordinaryEnd)
        return max(end - start, 0)
    }

    func distanceMeters(from source: Coordinate, to destination: Coordinate) -> Double {
        CLLocation(latitude: source.latitude, longitude: source.longitude).distance(
            from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        )
    }

    func clock(_ minute: Int) -> String {
        let normalized = max(minute, 0)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "约\(minutes)分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "约\(hours)小时" : "约\(hours)小时\(remainder)分钟"
    }

    func primaryOpeningWindow(for place: TravelPlace) -> OpeningWindow? {
        guard let text = place.openingHoursToday, !text.isEmpty,
              let expression = try? NSRegularExpression(
                  pattern: #"(\d{1,2}):(\d{2})\s*[-–—至]\s*(\d{1,2}):(\d{2})"#
              ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges == 5 else {
            return nil
        }
        let values = (1...4).compactMap { index -> Int? in
            guard let swiftRange = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[swiftRange])
        }
        guard values.count == 4 else { return nil }
        let start = values[0] * 60 + values[1]
        let end = values[2] * 60 + values[3]
        guard start < end, end <= 24 * 60 else { return nil }
        return OpeningWindow(startMinute: start, endMinute: end)
    }

    private func roundedToFive(_ value: Int) -> Int {
        max(Int((Double(value) / 5).rounded()) * 5, 5)
    }
}

/// Real first- and last-day limits derived from the selected long-distance
/// journey and its local transfer. Values are estimates shown to the traveler,
/// rather than hidden hard constraints.
struct TourismDayConstraints: Equatable, Sendable {
    var earliestStartMinute: Int?
    var latestEndMinute: Int?
    var startNote: String?
    var endNote: String?

    static let none = TourismDayConstraints()

    init(
        earliestStartMinute: Int? = nil,
        latestEndMinute: Int? = nil,
        startNote: String? = nil,
        endNote: String? = nil
    ) {
        self.earliestStartMinute = earliestStartMinute
        self.latestEndMinute = latestEndMinute
        self.startNote = startNote
        self.endNote = endNote
    }
}

struct TourismDayAssessment: Equatable, Sendable {
    let title: String
    let detail: String
    let badges: [String]
    let isOverCapacity: Bool
}

struct TourismDayAssessmentService {
    private let policy = TourismPlanningPolicy()

    func assess(
        day: ItineraryDay,
        pace: TripPace,
        mode: TravelMode,
        actualTravelMinutes: Int? = nil,
        constraints: TourismDayConstraints = .none
    ) -> TourismDayAssessment {
        let visitMinutes = day.stops.reduce(0) { $0 + policy.visitMinutes(for: $1, pace: pace) }
        let travelMinutes = actualTravelMinutes ?? policy.estimatedTravelMinutes(for: day, mode: mode)
        let dayMinutes = policy.estimatedDayMinutes(
            for: day,
            pace: pace,
            mode: mode,
            actualTravelMinutes: actualTravelMinutes
        )
        let availableMinutes = policy.availableDayMinutes(
            for: day,
            pace: pace,
            constraints: constraints
        )
        let hasMealStop = day.stops.contains { $0.interest == .food }
        let hasNightStop = day.stops.contains { $0.interest == .night }
        let knownOpeningHours = day.stops.filter { policy.primaryOpeningWindow(for: $0) != nil }.count
        let knownTicketPrices = day.stops.filter { $0.ticketQuote?.amountCNY != nil }.count
        let overCapacity = dayMinutes > availableMinutes

        var badges = [
            "停留\(policy.durationText(visitMinutes))",
            travelMinutes > 0 ? "移动\(policy.durationText(travelMinutes))" : "少移动",
            hasMealStop ? "餐食已入线" : "午餐有留白"
        ]
        if hasNightStop { badges.append("夜游置后") }
        if knownOpeningHours > 0 { badges.append("\(knownOpeningHours)处营业时段") }
        if knownTicketPrices > 0 { badges.append("\(knownTicketPrices)处门票价") }
        if constraints.earliestStartMinute != nil { badges.append("抵达日减负") }
        if constraints.latestEndMinute != nil { badges.append("返程留余量") }

        let arrangement = hasNightStop
            ? "相近地点被放在同一天，夜间体验留到天色落下之后。"
            : "相近地点被放在同一天，并为移动、用餐和临时停留留出余量。"
        let capacity = overCapacity
            ? "按当前节奏估算偏满，建议减一站或增加一天。"
            : "预计可在当天舒适时段内完成。"
        let boundaryNote: String
        if constraints.earliestStartMinute != nil, constraints.latestEndMinute != nil {
            boundaryNote = "已扣除抵达安顿与返程进站所需时间。"
        } else if constraints.earliestStartMinute != nil {
            boundaryNote = "已从抵达、接驳与安顿之后开始计算。"
        } else if constraints.latestEndMinute != nil {
            boundaryNote = "已为去返程枢纽和提前进站留出时间。"
        } else {
            boundaryNote = ""
        }
        let openingNote = knownOpeningHours > 0
            ? "已纳入可读取的今日营业时段，临时闭馆与预约仍需复核。"
            : "开放、闭馆与预约请在出发前复核。"
        return TourismDayAssessment(
            title: overCapacity ? "这一天仍有些拥挤" : "这一天为何这样展开",
            detail: arrangement + capacity + boundaryNote + openingNote,
            badges: badges,
            isOverCapacity: overCapacity
        )
    }
}
