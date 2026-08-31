import Foundation

enum PlanPacingLevel: Int, Comparable, Sendable {
    case comfortable
    case watch
    case rushed

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PlanPacingAssessment: Equatable, Sendable {
    let level: PlanPacingLevel
    let title: String
    let detail: String
    let suggestedDayCount: Int
    let overloadedDayIndices: [Int]
    let longTravelDayIndices: [Int]
    let canRelax: Bool

    var needsAttention: Bool { level != .comfortable }
}

struct RelaxedItineraryResult: Equatable, Sendable {
    let days: [ItineraryDay]
    let stillBusy: Bool
}

struct PlanPacingService {
    private let comfortableStopsPerDay = 2
    private let longTravelMinutes = 75
    private let rushedTravelMinutes = 120
    private let maximumDays = 7

    func assess(
        days: [ItineraryDay],
        travelMinutesByDay: [Int: Int] = [:],
        failedSegmentsByDay: [Int: Int] = [:],
        pace: TripPace
    ) -> PlanPacingAssessment {
        let orderedDays = days.sorted { $0.index < $1.index }
        let totalStops = orderedDays.reduce(0) { $0 + $1.stops.count }
        let overloadedDays = orderedDays
            .filter { $0.stops.count > comfortableStopsPerDay }
            .map(\.index)
        let longTravelDays = orderedDays
            .filter { (travelMinutesByDay[$0.index] ?? 0) > longTravelMinutes }
            .map(\.index)
        let failedSegmentCount = failedSegmentsByDay.values.reduce(0, +)

        let minimumRelaxedDays = Int(ceil(Double(totalStops) / Double(comfortableStopsPerDay)))
        var suggestedDayCount = max(orderedDays.count, minimumRelaxedDays)
        if !longTravelDays.isEmpty, totalStops > suggestedDayCount {
            suggestedDayCount += 1
        }
        suggestedDayCount = min(suggestedDayCount, min(maximumDays, max(totalStops, 1)))

        let maximumStops = orderedDays.map(\.stops.count).max() ?? 0
        let maximumTravel = travelMinutesByDay.values.max() ?? 0
        let level: PlanPacingLevel
        if maximumStops >= 4 || maximumTravel > rushedTravelMinutes {
            level = .rushed
        } else if !overloadedDays.isEmpty || !longTravelDays.isEmpty || pace != .relaxed || failedSegmentCount > 0 {
            level = .watch
        } else {
            level = .comfortable
        }

        var reasons: [String] = []
        if let first = overloadedDays.first,
           let day = orderedDays.first(where: { $0.index == first }) {
            reasons.append("第 \(first + 1) 天有 \(day.stops.count) 处停留")
        }
        if let first = longTravelDays.first, let minutes = travelMinutesByDay[first] {
            reasons.append("第 \(first + 1) 天市内移动约 \(minutes) 分钟")
        }
        if reasons.isEmpty, pace != .relaxed {
            reasons.append("当前采用“\(pace.title)”节奏")
        }
        if failedSegmentCount > 0 {
            reasons.append("还有 \(failedSegmentCount) 段路线等待复核")
        }

        let canRelax = totalStops > 0 && (level != .comfortable || pace != .relaxed)
        let title: String
        let detail: String
        switch level {
        case .comfortable:
            title = "脚步之间留有余地"
            detail = "每天约两处主要停留，午餐与休息也有自己的时间。"
        case .watch, .rushed:
            title = level == .rushed ? "这段行程有点赶" : "有几段脚步可以再松一点"
            let suggestion = suggestedDayCount > orderedDays.count
                ? "建议从 \(orderedDays.count) 天延长到 \(suggestedDayCount) 天"
                : "可以重新铺成每天约两处"
            detail = reasons.prefix(2).joined(separator: "；") + "。" + suggestion + "。"
        }

        return PlanPacingAssessment(
            level: level,
            title: title,
            detail: detail,
            suggestedDayCount: suggestedDayCount,
            overloadedDayIndices: overloadedDays,
            longTravelDayIndices: longTravelDays,
            canRelax: canRelax
        )
    }

    func makeRelaxedItinerary(
        from days: [ItineraryDay],
        travelMinutesByDay: [Int: Int] = [:],
        failedSegmentsByDay: [Int: Int] = [:],
        pace: TripPace
    ) -> RelaxedItineraryResult {
        let orderedDays = days.sorted { $0.index < $1.index }
        let stops = orderedDays.flatMap(\.stops)
        guard !stops.isEmpty else { return RelaxedItineraryResult(days: [], stillBusy: false) }

        let assessment = assess(
            days: orderedDays,
            travelMinutesByDay: travelMinutesByDay,
            failedSegmentsByDay: failedSegmentsByDay,
            pace: pace
        )
        let targetDayCount = assessment.suggestedDayCount
        let alreadyComfortable = orderedDays.allSatisfy { $0.stops.count <= comfortableStopsPerDay }
            && assessment.longTravelDayIndices.isEmpty
            && targetDayCount == orderedDays.count

        if alreadyComfortable {
            return RelaxedItineraryResult(
                days: orderedDays.enumerated().map { ItineraryDay(index: $0.offset, stops: $0.element.stops) },
                stillBusy: false
            )
        }

        let baseCount = stops.count / targetDayCount
        let remainder = stops.count % targetDayCount
        var cursor = 0
        var result: [ItineraryDay] = []
        for dayIndex in 0..<targetDayCount {
            let count = baseCount + (dayIndex < remainder ? 1 : 0)
            let end = cursor + count
            result.append(ItineraryDay(index: dayIndex, stops: Array(stops[cursor..<end])))
            cursor = end
        }

        return RelaxedItineraryResult(
            days: result,
            stillBusy: result.contains { $0.stops.count > comfortableStopsPerDay }
        )
    }
}
