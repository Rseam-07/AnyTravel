import CoreLocation
import Foundation
import MapKit

struct RoutePlanner {
    private let policy = TourismPlanningPolicy()

    func orderPlaces(
        _ places: [TravelPlace],
        from center: Coordinate,
        draft: TripDraft
    ) -> [ItineraryDay] {
        let uniquePlaces = deduplicatedPlaces(places)
        guard !uniquePlaces.isEmpty else { return [] }
        let dayCount = min(max(draft.dayCount, 1), uniquePlaces.count)
        let groups = spatiallyBalancedGroups(uniquePlaces, dayCount: dayCount, center: center)
            .sorted {
                distance(from: center, to: centroid(of: $0))
                    < distance(from: center, to: centroid(of: $1))
            }

        return groups.enumerated().map { dayIndex, group in
            ItineraryDay(
                index: dayIndex,
                stops: orderWithinDay(group, from: centroid(of: group))
            )
        }
    }

    func deduplicatedPlaces(_ places: [TravelPlace]) -> [TravelPlace] {
        var result: [TravelPlace] = []
        for place in places {
            if let duplicateIndex = result.firstIndex(where: { equivalentPlace($0, place) }) {
                if informationScore(for: place) > informationScore(for: result[duplicateIndex]) {
                    result[duplicateIndex] = place
                }
            } else {
                result.append(place)
            }
        }
        return result
    }

    func buildRoutes(
        for day: ItineraryDay,
        mode: TravelMode
    ) async throws -> RouteBuildResult {
        guard day.stops.count > 1 else {
            return RouteBuildResult(legs: [], failedSegments: 0)
        }

        var legs: [PlannedLeg] = []
        var failedSegments = 0

        for pairIndex in 0..<(day.stops.count - 1) {
            try Task.checkCancellation()
            let source = day.stops[pairIndex]
            let destination = day.stops[pairIndex + 1]
            let request = MKDirections.Request()
            request.source = mapItem(for: source)
            request.destination = mapItem(for: destination)
            request.transportType = mode.mapKitType
            request.requestsAlternateRoutes = false
            if mode == .transit {
                request.departureDate = .now
            }

            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first else {
                    failedSegments += 1
                    continue
                }
                legs.append(
                    PlannedLeg(
                        dayIndex: day.index,
                        sourceID: source.id,
                        destinationID: destination.id,
                        route: route
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedSegments += 1
            }
        }

        if legs.isEmpty, day.stops.count > 1 {
            throw PlanningError.routeUnavailable
        }

        return RouteBuildResult(legs: legs, failedSegments: failedSegments)
    }

    private func mapItem(for place: TravelPlace) -> MKMapItem {
        let coordinate = place.coordinate.clLocationCoordinate
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = place.name
        return item
    }

    private func distance(from source: Coordinate, to destination: Coordinate) -> CLLocationDistance {
        policy.distanceMeters(from: source, to: destination)
    }

    private func equivalentPlace(_ lhs: TravelPlace, _ rhs: TravelPlace) -> Bool {
        let lhsName = canonicalName(lhs.name)
        let rhsName = canonicalName(rhs.name)
        guard !lhsName.isEmpty, !rhsName.isEmpty else { return false }
        let separation = distance(from: lhs.coordinate, to: rhs.coordinate)
        if lhsName == rhsName {
            return separation < 600
        }
        let shorterCount = min(lhsName.count, rhsName.count)
        return separation < 120
            && shorterCount >= 4
            && (lhsName.contains(rhsName) || rhsName.contains(lhsName))
    }

    private func canonicalName(_ name: String) -> String {
        let folded = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_Hans_CN")
        )
        return folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func informationScore(for place: TravelPlace) -> Int {
        var score = min(place.address.count, 30)
        if place.openingHoursToday != nil { score += 20 }
        if place.openingHoursWeek != nil { score += 12 }
        if place.ticketQuote != nil { score += 18 }
        if place.source != "Apple Maps" { score += 4 }
        return score
    }

    private func spatiallyBalancedGroups(
        _ places: [TravelPlace],
        dayCount: Int,
        center: Coordinate
    ) -> [[TravelPlace]] {
        let baseSize = places.count / dayCount
        let remainder = places.count % dayCount
        let capacities = (0..<dayCount).map { baseSize + ($0 < remainder ? 1 : 0) }

        let ordinary = places.filter { $0.interest != .food && $0.interest != .night }
        let seedPool = ordinary.count >= dayCount ? ordinary : places
        var seeds: [TravelPlace] = []
        if let first = seedPool.min(by: {
            distance(from: center, to: $0.coordinate) < distance(from: center, to: $1.coordinate)
        }) {
            seeds.append(first)
        }
        while seeds.count < dayCount {
            let candidates = seedPool.filter { candidate in
                !seeds.contains(where: { $0.id == candidate.id })
            }
            guard let next = candidates.max(by: { lhs, rhs in
                minimumDistance(from: lhs, to: seeds) < minimumDistance(from: rhs, to: seeds)
            }) else { break }
            seeds.append(next)
        }

        var groups = seeds.map { [$0] }
        var remaining = places.filter { place in !seeds.contains(where: { $0.id == place.id }) }
        remaining.sort { lhs, rhs in
            specialPriority(lhs) > specialPriority(rhs)
        }

        for place in remaining {
            let candidates = groups.indices.filter { groups[$0].count < capacities[$0] }
            let selectedIndex = (candidates.isEmpty ? Array(groups.indices) : candidates).min { lhs, rhs in
                assignmentCost(place, group: groups[lhs]) < assignmentCost(place, group: groups[rhs])
            } ?? 0
            groups[selectedIndex].append(place)
        }
        return groups.filter { !$0.isEmpty }
    }

    private func orderWithinDay(
        _ places: [TravelPlace],
        from start: Coordinate
    ) -> [TravelPlace] {
        var ordinary = places.filter { $0.interest != .food && $0.interest != .night }
        var foods = places.filter { $0.interest == .food }
        var nights = places.filter { $0.interest == .night }
        var ordered: [TravelPlace] = []
        var cursor = start

        if !ordinary.isEmpty {
            let first = removeNearest(from: cursor, in: &ordinary)
            ordered.append(first)
            cursor = first.coordinate
        }

        // A food stop after the first main visit naturally becomes lunch and
        // prevents a duplicate generic meal break in the timeline.
        if !foods.isEmpty {
            let meal = removeNearest(from: cursor, in: &foods)
            ordered.append(meal)
            cursor = meal.coordinate
        }

        while !ordinary.isEmpty {
            let next = removeNearest(from: cursor, in: &ordinary)
            ordered.append(next)
            cursor = next.coordinate
        }
        while !foods.isEmpty {
            let next = removeNearest(from: cursor, in: &foods)
            ordered.append(next)
            cursor = next.coordinate
        }
        while !nights.isEmpty {
            let next = removeNearest(from: cursor, in: &nights)
            ordered.append(next)
            cursor = next.coordinate
        }
        return ordered
    }

    private func removeNearest(from coordinate: Coordinate, in places: inout [TravelPlace]) -> TravelPlace {
        let index = places.indices.min {
            nextStopCost(places[$0], from: coordinate) < nextStopCost(places[$1], from: coordinate)
        } ?? places.startIndex
        return places.remove(at: index)
    }

    private func nextStopCost(_ place: TravelPlace, from coordinate: Coordinate) -> Double {
        let spatial = distance(from: coordinate, to: place.coordinate)
        guard let window = policy.primaryOpeningWindow(for: place) else { return spatial + 1_800 }
        // A venue closing earlier may move ahead of a slightly nearer venue.
        // The penalty is deliberately bounded so geography still dominates.
        let minutesAfterFive = max(window.endMinute - 17 * 60, 0)
        return spatial + Double(min(minutesAfterFive * 8, 3_600))
    }

    private func minimumDistance(from place: TravelPlace, to seeds: [TravelPlace]) -> Double {
        seeds.map { distance(from: place.coordinate, to: $0.coordinate) }.min() ?? 0
    }

    private func assignmentCost(_ place: TravelPlace, group: [TravelPlace]) -> Double {
        let spatial = distance(from: place.coordinate, to: centroid(of: group))
        let duplicateTimeWindowPenalty: Double
        if place.interest == .night, group.contains(where: { $0.interest == .night }) {
            duplicateTimeWindowPenalty = 20_000
        } else if place.interest == .food, group.contains(where: { $0.interest == .food }) {
            duplicateTimeWindowPenalty = 12_000
        } else {
            duplicateTimeWindowPenalty = 0
        }
        return spatial + duplicateTimeWindowPenalty
    }

    private func specialPriority(_ place: TravelPlace) -> Int {
        switch place.interest {
        case .night: 2
        case .food: 1
        default: 0
        }
    }

    private func centroid(of places: [TravelPlace]) -> Coordinate {
        guard !places.isEmpty else { return Coordinate(latitude: 0, longitude: 0) }
        let latitude = places.reduce(0) { $0 + $1.coordinate.latitude } / Double(places.count)
        let longitude = places.reduce(0) { $0 + $1.coordinate.longitude } / Double(places.count)
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
