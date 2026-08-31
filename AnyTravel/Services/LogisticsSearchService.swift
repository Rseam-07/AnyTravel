import CoreLocation
import Foundation
import MapKit

struct AccommodationDiscoveryResult: Sendable {
    var options: [AccommodationOption]
    var accessPoints: [AccessPoint]
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
        let queries = ["\(draft.destination) 酒店", "\(draft.destination) 民宿"]
        var seen = Set<String>()
        var candidates: [(MKMapItem, Double)] = []

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = destination.region
            request.resultTypes = .pointOfInterest

            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    continue
                }
                let coordinate = Coordinate(item.anyTravelCoordinate)
                let key = "\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))|\(Int(coordinate.latitude * 10_000))|\(Int(coordinate.longitude * 10_000))"
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
                let lhsMetro = Self.nearestDistance(from: Coordinate(lhs.0.anyTravelCoordinate), kind: .metro, in: accessPoints) ?? 8_000
                let rhsMetro = Self.nearestDistance(from: Coordinate(rhs.0.anyTravelCoordinate), kind: .metro, in: accessPoints) ?? 8_000
                return lhs.1 + lhsMetro * 0.22 < rhs.1 + rhsMetro * 0.22
            }
            .prefix(10)
            .map { item, attractionDistance in
                let coordinate = Coordinate(item.anyTravelCoordinate)
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
                    name: item.name ?? "住宿",
                    address: item.anyTravelAddress,
                    coordinate: coordinate,
                    officialWebsiteURL: item.url,
                    attractionDistanceMeters: attractionDistance,
                    accessDistances: distances,
                    nearestAccessPoints: nearest,
                    quotes: Self.channelPlaceholders(officialURL: item.url, hasDates: draft.logistics.hasDates),
                    recommendationReasons: reasons
                )
            }

        return AccommodationDiscoveryResult(options: Array(options), accessPoints: accessPoints)
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
