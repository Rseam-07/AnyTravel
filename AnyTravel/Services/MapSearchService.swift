import CoreLocation
import Foundation
import MapKit

struct MapSearchService {
    private let amapClient: AMapPlaceClient

    init(amapClient: AMapPlaceClient = AMapPlaceClient()) {
        self.amapClient = amapClient
    }

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

            if amapClient.isConfigured,
               let amapPlaces = try? await amapClient.search(
                   keywords: interest.searchTerm,
                   city: draft.destination,
                   interest: interest,
                   limit: min(max(targetCount, 6), 20)
               ) {
                for place in amapPlaces {
                    guard distance(from: center, to: place.coordinate) <= 45_000 else { continue }
                    let key = deduplicationKey(
                        name: place.name,
                        coordinate: place.coordinate.clLocationCoordinate
                    )
                    guard seen.insert(key).inserted else { continue }
                    buckets[interest, default: []].append(place)
                }
                buckets[interest]?.sort {
                    distance(from: center, to: $0.coordinate) < distance(from: center, to: $1.coordinate)
                }
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

    func discoverAttractionCandidates(
        around destination: DestinationResolution,
        draft: TripDraft,
        limit: Int = 60
    ) async throws -> [TravelPlace] {
        let activeInterests = TripInterest.allCases.filter(draft.interests.contains)
        let interestQueries = (activeInterests.isEmpty ? [.gardens, .culture, .nature] : activeInterests)
            .prefix(5)
            .map { (query: $0.searchTerm, interest: $0, bonus: 76.0) }
        let querySpecs: [(query: String, interest: TripInterest, bonus: Double)] = [
            ("热门景点", .culture, 112),
            ("必去景点", .culture, 106),
            ("地标 名胜古迹", .gardens, 96)
        ] + interestQueries
        let center = CLLocation(
            latitude: destination.coordinate.latitude,
            longitude: destination.coordinate.longitude
        )
        var candidates: [TravelPlace] = []

        for spec in querySpecs {
            let mapRequest = MKLocalSearch.Request()
            mapRequest.naturalLanguageQuery = "\(destination.title) \(spec.query)"
            mapRequest.region = destination.region
            mapRequest.resultTypes = .pointOfInterest
            if let response = try? await MKLocalSearch(request: mapRequest).start() {
                for (index, item) in response.mapItems.prefix(20).enumerated() {
                    guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                          isLikelyAttraction(name, interest: spec.interest) else { continue }
                    let coordinate = item.anyTravelCoordinate
                    let distanceMeters = center.distance(
                        from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    )
                    guard distanceMeters <= 60_000 else { continue }
                    let score = spec.bonus - Double(index) * 2.2 - min(distanceMeters / 10_000, 8)
                    mergeCandidate(
                        TravelPlace(
                            name: name,
                            address: item.anyTravelAddress,
                            coordinate: Coordinate(coordinate),
                            interest: spec.interest,
                            source: "Apple Maps · 在线搜索",
                            popularity: AttractionPopularity(
                                score: score,
                                evidence: ["“\(spec.query)”在线结果第 \(index + 1) 位"]
                            )
                        ),
                        into: &candidates
                    )
                }
            }

            if amapClient.isConfigured,
               let amapPlaces = try? await amapClient.search(
                   keywords: spec.query,
                   city: draft.destination,
                   interest: spec.interest,
                   limit: 20
               ) {
                for (index, original) in amapPlaces.enumerated() {
                    guard isLikelyAttraction(original.name, interest: spec.interest),
                          distance(from: center, to: original.coordinate) <= 60_000 else { continue }
                    var place = original
                    let existing = place.popularity ?? AttractionPopularity(score: 0)
                    place.popularity = AttractionPopularity(
                        score: existing.score + spec.bonus - Double(index) * 1.6,
                        rating: existing.rating,
                        evidence: existing.evidence + ["“\(spec.query)”高德结果第 \(index + 1) 位"]
                    )
                    mergeCandidate(place, into: &candidates)
                }
            }
        }

        var ranked = candidates.sorted {
            let lhsScore = $0.popularity?.score ?? 0
            let rhsScore = $1.popularity?.score ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return distance(from: center, to: $0.coordinate) < distance(from: center, to: $1.coordinate)
        }
        for index in ranked.indices {
            var popularity = ranked[index].popularity ?? AttractionPopularity(score: 0)
            popularity.rank = index + 1
            popularity.evidence = Array(NSOrderedSet(array: popularity.evidence).array.compactMap { $0 as? String }.prefix(3))
            ranked[index].popularity = popularity
        }
        let result = Array(ranked.prefix(min(max(limit, 1), 80)))
        guard result.count >= 2 else { throw PlanningError.placesNotFound }
        return result
    }

    func searchPlaces(
        matching query: String,
        around destination: DestinationResolution,
        interest: TripInterest
    ) async throws -> [TravelPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(destination.title) \(trimmed)"
        request.region = destination.region
        request.resultTypes = .pointOfInterest

        let response = try await MKLocalSearch(request: request).start()
        let center = CLLocation(
            latitude: destination.coordinate.latitude,
            longitude: destination.coordinate.longitude
        )
        var seen = Set<String>()

        var places = response.mapItems.compactMap { item -> TravelPlace? in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
                return nil
            }
            let coordinate = item.anyTravelCoordinate
            guard center.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= 60_000 else {
                return nil
            }
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
        if amapClient.isConfigured,
           let amapPlaces = try? await amapClient.search(
               keywords: trimmed,
               city: destination.title,
               interest: interest,
               limit: 12
           ) {
            for place in amapPlaces {
                guard distance(from: center, to: place.coordinate) <= 60_000 else { continue }
                let key = deduplicationKey(name: place.name, coordinate: place.coordinate.clLocationCoordinate)
                guard seen.insert(key).inserted else { continue }
                places.append(place)
            }
        }

        return Array(places.sorted {
            distance(from: center, to: $0.coordinate) < distance(from: center, to: $1.coordinate)
        }.prefix(12))
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

    private func mergeCandidate(_ candidate: TravelPlace, into candidates: inout [TravelPlace]) {
        let candidateName = canonicalName(candidate.name)
        let candidateLocation = CLLocation(
            latitude: candidate.coordinate.latitude,
            longitude: candidate.coordinate.longitude
        )
        let duplicateIndex = candidates.firstIndex { existing in
            let existingName = canonicalName(existing.name)
            let comparableName = existingName == candidateName
                || min(existingName.count, candidateName.count) >= 4
                    && (existingName.contains(candidateName) || candidateName.contains(existingName))
            guard comparableName else { return false }
            return candidateLocation.distance(
                from: CLLocation(
                    latitude: existing.coordinate.latitude,
                    longitude: existing.coordinate.longitude
                )
            ) < 500
        }
        guard let duplicateIndex else {
            candidates.append(candidate)
            return
        }

        let old = candidates[duplicateIndex]
        let oldPopularity = old.popularity ?? AttractionPopularity(score: 0)
        let newPopularity = candidate.popularity ?? AttractionPopularity(score: 0)
        let shouldUseCandidate = informationScore(candidate) > informationScore(old)
        var merged = shouldUseCandidate ? candidate : old
        merged.popularity = AttractionPopularity(
            score: max(oldPopularity.score, newPopularity.score) + 18,
            rating: max(oldPopularity.rating ?? 0, newPopularity.rating ?? 0).nonZero,
            evidence: oldPopularity.evidence + newPopularity.evidence + ["多个在线来源同时出现"]
        )
        candidates[duplicateIndex] = merged
    }

    private func canonicalName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func informationScore(_ place: TravelPlace) -> Int {
        var score = min(place.address.count, 30)
        if place.openingHoursToday != nil { score += 20 }
        if place.openingHoursWeek != nil { score += 12 }
        if place.popularity?.rating != nil { score += 10 }
        if place.source.contains("高德") { score += 5 }
        return score
    }

    private func isLikelyAttraction(_ name: String, interest: TripInterest) -> Bool {
        if interest == .food { return true }
        let excluded = ["旅行社", "停车场", "游客中心", "售票处", "洗手间", "酒店", "宾馆", "公寓"]
        return !excluded.contains(where: name.contains)
    }
}

private extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
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
