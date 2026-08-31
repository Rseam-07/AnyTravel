import CoreLocation
import Foundation
import MapKit

struct MapSearchService {
    func resolveDestination(_ query: String) async throws -> DestinationResolution {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlanningError.emptyDestination }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        guard let mapItem = response.mapItems.first else {
            throw PlanningError.destinationNotFound
        }

        let coordinate = mapItem.anyTravelCoordinate
        let region = normalizedCityRegion(
            proposed: response.boundingRegion,
            around: coordinate
        )

        return DestinationResolution(
            title: mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? trimmed,
            coordinate: Coordinate(coordinate),
            region: region
        )
    }

    func discoverPlaces(
        around destination: DestinationResolution,
        draft: TripDraft
    ) async throws -> [TravelPlace] {
        let interests = TripInterest.allCases.filter(draft.interests.contains)
        let activeInterests = interests.isEmpty ? [.gardens, .food] : interests
        let targetCount = min(max(draft.dayCount, 1) * draft.pace.stopsPerDay, 20)
        let center = CLLocation(
            latitude: destination.coordinate.latitude,
            longitude: destination.coordinate.longitude
        )

        var buckets: [TripInterest: [TravelPlace]] = [:]
        var seen = Set<String>()

        for interest in activeInterests {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(draft.destination) \(interest.searchTerm)"
            request.region = destination.region
            request.resultTypes = .pointOfInterest

            do {
                let response = try await MKLocalSearch(request: request).start()
                let places = response.mapItems.compactMap { item -> TravelPlace? in
                    guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
                        return nil
                    }

                    let coordinate = item.anyTravelCoordinate
                    let distance = center.distance(
                        from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    )
                    guard distance <= 45_000 else { return nil }

                    let key = deduplicationKey(name: name, coordinate: coordinate)
                    guard seen.insert(key).inserted else { return nil }

                    return TravelPlace(
                        name: name,
                        address: item.anyTravelAddress,
                        coordinate: Coordinate(coordinate),
                        interest: interest
                    )
                }
                .sorted {
                    distance(from: center, to: $0.coordinate) < distance(from: center, to: $1.coordinate)
                }

                buckets[interest] = Array(places.prefix(max(targetCount, 6)))
            } catch {
                buckets[interest] = []
            }
        }

        var selected: [TravelPlace] = []
        var index = 0
        while selected.count < targetCount {
            var appended = false
            for interest in activeInterests {
                guard let bucket = buckets[interest], bucket.indices.contains(index) else { continue }
                selected.append(bucket[index])
                appended = true
                if selected.count == targetCount { break }
            }
            if !appended { break }
            index += 1
        }

        guard selected.count >= min(2, targetCount) else {
            throw PlanningError.placesNotFound
        }

        return selected
    }

    private func normalizedCityRegion(
        proposed: MKCoordinateRegion,
        around coordinate: CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        let latitudeDelta = proposed.span.latitudeDelta
        let longitudeDelta = proposed.span.longitudeDelta
        let isUsefulCitySpan = latitudeDelta >= 0.04 && latitudeDelta <= 1.2
            && longitudeDelta >= 0.04 && longitudeDelta <= 1.2

        if isUsefulCitySpan {
            return proposed
        }

        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.24)
        )
    }

    private func deduplicationKey(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
        let latitude = Int((coordinate.latitude * 10_000).rounded())
        let longitude = Int((coordinate.longitude * 10_000).rounded())
        return "\(normalizedName)|\(latitude)|\(longitude)"
    }

    private func distance(from center: CLLocation, to coordinate: Coordinate) -> CLLocationDistance {
        center.distance(
            from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension MKMapItem {
    var anyTravelCoordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            location.coordinate
        } else {
            placemark.coordinate
        }
    }

    var anyTravelAddress: String {
        if #available(iOS 26.0, *) {
            return address?.shortAddress ?? address?.fullAddress ?? "地址以地图详情为准"
        }

        return placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "地址以地图详情为准"
    }
}
