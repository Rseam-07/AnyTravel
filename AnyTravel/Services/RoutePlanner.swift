import CoreLocation
import Foundation
import MapKit

struct RoutePlanner {
    func orderPlaces(
        _ places: [TravelPlace],
        from center: Coordinate,
        draft: TripDraft
    ) -> [ItineraryDay] {
        var remaining = places
        var ordered: [TravelPlace] = []
        var cursor = center

        while !remaining.isEmpty {
            guard let nearestIndex = remaining.indices.min(by: {
                distance(from: cursor, to: remaining[$0].coordinate)
                    < distance(from: cursor, to: remaining[$1].coordinate)
            }) else { break }

            let next = remaining.remove(at: nearestIndex)
            ordered.append(next)
            cursor = next.coordinate
        }

        let perDay = draft.pace.stopsPerDay
        return (0..<max(draft.dayCount, 1)).compactMap { dayIndex in
            let start = dayIndex * perDay
            guard start < ordered.count else { return nil }
            let end = min(start + perDay, ordered.count)
            return ItineraryDay(index: dayIndex, stops: Array(ordered[start..<end]))
        }
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
        CLLocation(latitude: source.latitude, longitude: source.longitude).distance(
            from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        )
    }
}
