import CoreLocation
import Foundation
import MapKit

struct AccommodationDiscoveryResult: Sendable {
    var options: [AccommodationOption]
    var accessPoints: [AccessPoint]
}

private struct AccommodationSearchSpec: Sendable {
    var query: String
    var center: Coordinate
    var latitudeDelta: Double
    var longitudeDelta: Double
}

private struct AccommodationSearchHit: Sendable {
    var name: String
    var address: String
    var coordinate: Coordinate
    var officialWebsiteURL: URL?
}

struct LogisticsSearchService {
    func discoverAccommodations(
        around destination: DestinationResolution,
        itineraryDays: [ItineraryDay],
        draft: TripDraft
    ) async -> AccommodationDiscoveryResult {
        let accessPoints = await discoverAccessPoints(around: destination, destinationName: draft.destination)
        let itineraryCoordinates = itineraryDays.flatMap(\.stops).map(\.coordinate)
        let referenceCoordinates = itineraryCoordinates.isEmpty ? [destination.coordinate] : itineraryCoordinates
        let destinationQueries = [
            "\(draft.destination) 酒店",
            "\(draft.destination) 精品酒店",
            "\(draft.destination) 连锁酒店",
            "\(draft.destination) 民宿 客栈",
            "\(draft.destination) 公寓酒店",
            "\(draft.destination) 青年旅舍"
        ]
        var specs = destinationQueries.map {
            AccommodationSearchSpec(
                query: $0,
                center: destination.coordinate,
                latitudeDelta: max(destination.region.span.latitudeDelta, 0.10),
                longitudeDelta: max(destination.region.span.longitudeDelta, 0.10)
            )
        }
        for day in itineraryDays.prefix(4) where !day.stops.isEmpty {
            let coordinates = day.stops.map(\.coordinate)
            specs.append(
                AccommodationSearchSpec(
                    query: "酒店 住宿",
                    center: Coordinate(
                        latitude: coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count),
                        longitude: coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
                    ),
                    latitudeDelta: 0.075,
                    longitudeDelta: 0.075
                )
            )
        }
        var seen = Set<String>()
        var candidates: [(AccommodationSearchHit, Double)] = []

        let batches = await withTaskGroup(of: [AccommodationSearchHit].self) { group in
            for spec in specs {
                group.addTask { await Self.searchAccommodations(spec) }
            }
            var result: [[AccommodationSearchHit]] = []
            for await batch in group { result.append(batch) }
            return result
        }

        for batch in batches {
            for item in batch {
                let name = item.name
                let coordinate = item.coordinate
                let key = "\(AccommodationIdentity.normalizedName(name))|\(Int(coordinate.latitude * 10_000))|\(Int(coordinate.longitude * 10_000))"
                guard seen.insert(key).inserted else { continue }

                let fromDestination = Self.distance(from: destination.coordinate, to: coordinate)
                guard fromDestination <= 45_000 else { continue }
                let averageAttractionDistance = referenceCoordinates
                    .map { Self.distance(from: $0, to: coordinate) }
                    .reduce(0, +) / Double(referenceCoordinates.count)
                candidates.append((item, averageAttractionDistance))
            }
        }

        let options = candidates
            .sorted { lhs, rhs in
                let lhsMetro = Self.nearestDistance(from: lhs.0.coordinate, kind: .metro, in: accessPoints) ?? 8_000
                let rhsMetro = Self.nearestDistance(from: rhs.0.coordinate, kind: .metro, in: accessPoints) ?? 8_000
                return lhs.1 + lhsMetro * 0.22 < rhs.1 + rhsMetro * 0.22
            }
            .prefix(45)
            .map { item, attractionDistance in
                let coordinate = item.coordinate
                var distances: [AccessPointKind: Double] = [:]
                var nearest: [AccessPointKind: AccessPoint] = [:]
                for kind in [AccessPointKind.metro, .rail, .airport] {
                    guard let result = Self.nearestAccessPoint(from: coordinate, kind: kind, in: accessPoints) else {
                        continue
                    }
                    distances[kind] = result.distance
                    nearest[kind] = result.point
                }

                var reasons = ["到行程景点平均 \(attractionDistance.anyTravelDistanceText)"]
                if let metroDistance = distances[.metro] {
                    reasons.append("距地铁约 \(metroDistance.anyTravelDistanceText)")
                } else if let railDistance = distances[.rail] {
                    reasons.append("距高铁站约 \(railDistance.anyTravelDistanceText)")
                }

                return AccommodationOption(
                    name: item.name,
                    address: item.address,
                    coordinate: coordinate,
                    officialWebsiteURL: item.officialWebsiteURL,
                    attractionDistanceMeters: attractionDistance,
                    accessDistances: distances,
                    nearestAccessPoints: nearest,
                    quotes: Self.channelPlaceholders(officialURL: item.officialWebsiteURL, hasDates: draft.logistics.hasDates),
                    recommendationReasons: reasons
                )
            }

        return AccommodationDiscoveryResult(options: Array(options), accessPoints: accessPoints)
    }

    func mergingCatalog(
        _ catalog: [AccommodationCatalogEntry],
        into discovery: AccommodationDiscoveryResult,
        around destination: DestinationResolution,
        itineraryDays: [ItineraryDay],
        draft: TripDraft
    ) async -> AccommodationDiscoveryResult {
        let itineraryCoordinates = itineraryDays.flatMap(\.stops).map(\.coordinate)
        let referenceCoordinates = itineraryCoordinates.isEmpty ? [destination.coordinate] : itineraryCoordinates
        var options = discovery.options
        let locatedCatalog = await Self.locatingCatalog(catalog, around: destination)

        for entry in locatedCatalog {
            guard let entryCoordinate = entry.coordinate,
                  Self.distance(from: destination.coordinate, to: entryCoordinate) <= 60_000 else { continue }
            if let index = options.firstIndex(where: {
                AccommodationIdentity.isSameProperty(
                    name: $0.name,
                    coordinate: $0.coordinate,
                    brand: $0.brand,
                    and: entry.name,
                    coordinate: entryCoordinate,
                    brand: entry.brand
                )
            }) {
                options[index].brand = entry.brand ?? options[index].brand
                options[index].starRating = entry.starRating ?? options[index].starRating
                options[index].guestRating = entry.guestRating ?? options[index].guestRating
                options[index].imageURL = entry.imageURL ?? options[index].imageURL
                options[index].amenities = entry.amenities.isEmpty ? options[index].amenities : entry.amenities
                options[index].tags = entry.tags.isEmpty ? options[index].tags : entry.tags
                if options[index].officialWebsiteURL == nil {
                    options[index].officialWebsiteURL = AccommodationIdentity.officialWebsite(name: entry.name, brand: entry.brand)
                    if let officialURL = options[index].officialWebsiteURL,
                       !options[index].quotes.contains(where: { $0.provider == .propertyOfficial }) {
                        options[index].quotes.append(
                            ProviderQuote(
                                provider: .propertyOfficial,
                                unit: .perNight,
                                kind: .checkOnProvider,
                                bookingURL: officialURL,
                                note: "品牌官网直订价需在页面确认"
                            )
                        )
                    }
                }
                options[index].quotes = Self.mergingQuotes(options[index].quotes, with: entry.quotes)
                continue
            }

            let attractionDistance = referenceCoordinates
                .map { Self.distance(from: $0, to: entryCoordinate) }
                .reduce(0, +) / Double(referenceCoordinates.count)
            var distances: [AccessPointKind: Double] = [:]
            var nearest: [AccessPointKind: AccessPoint] = [:]
            for kind in [AccessPointKind.metro, .rail, .airport] {
                guard let result = Self.nearestAccessPoint(from: entryCoordinate, kind: kind, in: discovery.accessPoints) else {
                    continue
                }
                distances[kind] = result.distance
                nearest[kind] = result.point
            }
            var reasons = ["到行程景点平均 \(attractionDistance.anyTravelDistanceText)"]
            if let metroDistance = distances[.metro] {
                reasons.append("距地铁约 \(metroDistance.anyTravelDistanceText)")
            }
            if let starRating = entry.starRating, starRating > 0 {
                reasons.append("约 \(starRating.formatted(.number.precision(.fractionLength(0...1)))) 星级")
            }
            let officialURL = AccommodationIdentity.officialWebsite(name: entry.name, brand: entry.brand)
            var quotes = Self.channelPlaceholders(officialURL: officialURL, hasDates: draft.logistics.hasDates)
            quotes = Self.mergingQuotes(quotes, with: entry.quotes)
            options.append(
                AccommodationOption(
                    name: entry.name,
                    address: entry.address,
                    coordinate: entryCoordinate,
                    officialWebsiteURL: officialURL,
                    brand: entry.brand,
                    starRating: entry.starRating,
                    guestRating: entry.guestRating,
                    imageURL: entry.imageURL,
                    amenities: entry.amenities,
                    tags: entry.tags,
                    attractionDistanceMeters: attractionDistance,
                    accessDistances: distances,
                    nearestAccessPoints: nearest,
                    quotes: quotes,
                    recommendationReasons: reasons
                )
            )
        }

        options.sort { lhs, rhs in
            let lhsMetro = lhs.accessDistances[.metro] ?? 8_000
            let rhsMetro = rhs.accessDistances[.metro] ?? 8_000
            return lhs.attractionDistanceMeters + lhsMetro * 0.22
                < rhs.attractionDistanceMeters + rhsMetro * 0.22
        }
        return AccommodationDiscoveryResult(options: Array(options.prefix(60)), accessPoints: discovery.accessPoints)
    }

    private static func locatingCatalog(
        _ catalog: [AccommodationCatalogEntry],
        around destination: DestinationResolution
    ) async -> [AccommodationCatalogEntry] {
        let missing = catalog.indices.filter { catalog[$0].coordinate == nil }.prefix(16)
        guard !missing.isEmpty else { return catalog }
        var output = catalog
        // MapKit search objects are main-actor isolated under Swift 6. Keep this
        // bounded fallback on the main actor instead of moving them through a
        // task group; most provider listings already carry coordinates.
        for index in missing where output.indices.contains(index) {
            let entry = output[index]
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(destination.title) \(entry.name)"
            request.region = destination.region
            request.resultTypes = .pointOfInterest
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            let requestedName = AccommodationIdentity.normalizedName(entry.name)
            let match = response.mapItems
                .filter { item in
                    guard let name = item.name else { return false }
                    let candidate = AccommodationIdentity.normalizedName(name)
                    return candidate == requestedName
                        || candidate.contains(requestedName)
                        || requestedName.contains(candidate)
                }
                .min { lhs, rhs in
                    Self.distance(from: destination.coordinate, to: Coordinate(lhs.anyTravelCoordinate))
                        < Self.distance(from: destination.coordinate, to: Coordinate(rhs.anyTravelCoordinate))
                }
            output[index].coordinate = match.map { Coordinate($0.anyTravelCoordinate) }
        }
        return output
    }

    private static func mergingQuotes(
        _ existing: [ProviderQuote],
        with incoming: [ProviderQuote]
    ) -> [ProviderQuote] {
        var result = existing
        let concreteProviders = Set(incoming.filter { $0.amountCNY != nil }.map(\.provider))
        result.removeAll {
            concreteProviders.contains($0.provider)
                && $0.amountCNY == nil
                && ($0.kind == .checkOnProvider || $0.kind == .requiresPartnerAccess)
        }
        for quote in incoming {
            let index = result.firstIndex {
                $0.provider == quote.provider
                    && $0.unit == quote.unit
                    && normalizedQuoteText($0.roomName) == normalizedQuoteText(quote.roomName)
                    && normalizedQuoteText($0.mealPlan) == normalizedQuoteText(quote.mealPlan)
                    && normalizedQuoteText($0.cancellationPolicy) == normalizedQuoteText(quote.cancellationPolicy)
            }
            guard let index else {
                result.append(quote)
                continue
            }
            let oldAmount = result[index].amountCNY
            let newAmount = quote.amountCNY
            if oldAmount == nil && newAmount != nil
                || oldAmount != nil && newAmount != nil && newAmount! < oldAmount!
                || oldAmount == newAmount && (quote.capturedAt ?? .distantPast) > (result[index].capturedAt ?? .distantPast) {
                result[index] = quote
            }
        }
        return result.sorted {
            if ($0.amountCNY != nil) != ($1.amountCNY != nil) { return $0.amountCNY != nil }
            if ($0.amountCNY ?? .max) != ($1.amountCNY ?? .max) {
                return ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max)
            }
            return $0.provider.title < $1.provider.title
        }
    }

    private static func normalizedQuoteText(_ value: String?) -> String {
        (value ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func searchAccommodations(_ spec: AccommodationSearchSpec) async -> [AccommodationSearchHit] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = spec.query
        request.region = MKCoordinateRegion(
            center: spec.center.clLocationCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: spec.latitudeDelta,
                longitudeDelta: spec.longitudeDelta
            )
        )
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let accommodationWords = ["酒店", "宾馆", "旅馆", "客栈", "民宿", "公寓", "青旅", "旅舍", "饭店", "度假村"]
        return response.mapItems.compactMap { item in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            guard item.pointOfInterestCategory == .hotel || accommodationWords.contains(where: name.contains) else {
                return nil
            }
            return AccommodationSearchHit(
                name: name,
                address: item.anyTravelAddress,
                coordinate: Coordinate(item.anyTravelCoordinate),
                officialWebsiteURL: item.url
            )
        }
    }

    func discoverAccessPoints(
        around destination: DestinationResolution,
        destinationName: String
    ) async -> [AccessPoint] {
        let searches: [(AccessPointKind, String)] = [
            (.rail, "\(destinationName) 火车站 高铁站"),
            (.airport, "\(destinationName) 机场"),
            (.metro, "\(destinationName) 地铁站")
        ]
        var points: [AccessPoint] = []
        var seen = Set<String>()

        for (kind, query) in searches {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = destination.region
            request.resultTypes = [.pointOfInterest, .address]
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }

            for item in response.mapItems.prefix(kind == .metro ? 12 : 5) {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    continue
                }
                let coordinate = Coordinate(item.anyTravelCoordinate)
                let key = "\(kind.rawValue)|\(name)"
                guard seen.insert(key).inserted else { continue }
                guard Self.distance(from: destination.coordinate, to: coordinate) <= 90_000 else { continue }
                points.append(AccessPoint(name: name, coordinate: coordinate, kind: kind))
            }
        }
        return points
    }

    private static func channelPlaceholders(officialURL: URL?, hasDates: Bool) -> [ProviderQuote] {
        let note = hasDates ? "按入住日期到渠道核价" : "补充入住日期后核价"
        var quotes = [
            ProviderQuote(
                provider: .ctrip,
                unit: .perNight,
                kind: .checkOnProvider,
                bookingURL: URL(string: "https://hotels.ctrip.com/"),
                note: note
            ),
            ProviderQuote(
                provider: .qunar,
                unit: .perNight,
                kind: .checkOnProvider,
                bookingURL: URL(string: "https://hotel.qunar.com/"),
                note: note
            ),
            ProviderQuote(
                provider: .tongcheng,
                unit: .perNight,
                kind: .checkOnProvider,
                bookingURL: URL(string: "https://m.ly.com/hotel/"),
                note: note
            ),
            ProviderQuote(
                provider: .tripCom,
                unit: .perNight,
                kind: .checkOnProvider,
                bookingURL: URL(string: "https://www.trip.com/hotels/"),
                note: note
            ),
            ProviderQuote(
                provider: .rollingGo,
                unit: .perNight,
                kind: .requiresPartnerAccess,
                note: "免费实时库存适配器已预留"
            )
        ]
        if let officialURL {
            quotes.append(
                ProviderQuote(
                    provider: .propertyOfficial,
                    unit: .perNight,
                    kind: .checkOnProvider,
                    bookingURL: officialURL,
                    note: "官网直订价需在页面确认"
                )
            )
        }
        return quotes
    }

    private static func nearestDistance(
        from coordinate: Coordinate,
        kind: AccessPointKind,
        in points: [AccessPoint]
    ) -> Double? {
        nearestAccessPoint(from: coordinate, kind: kind, in: points)?.distance
    }

    private static func nearestAccessPoint(
        from coordinate: Coordinate,
        kind: AccessPointKind,
        in points: [AccessPoint]
    ) -> (point: AccessPoint, distance: Double)? {
        points
            .filter { $0.kind == kind }
            .map { ($0, distance(from: coordinate, to: $0.coordinate)) }
            .min { $0.1 < $1.1 }
    }

    static func distance(from lhs: Coordinate, to rhs: Coordinate) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        )
    }
}
