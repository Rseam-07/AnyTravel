import Foundation
import MapKit

/// Shared offline destination snapshot generated from the Web harvesting pipeline.
struct DomesticGuideKnowledgeStore {
    private let cities: [GuideCity]

    static let shared = DomesticGuideKnowledgeStore(bundle: .main)

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "DomesticGuideKnowledge", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(GuideDocument.self, from: data) else {
            cities = []
            return
        }
        cities = document.cities
    }

    init(data: Data) throws {
        cities = try JSONDecoder().decode(GuideDocument.self, from: data).cities
    }

    func resolveDestination(_ query: String) -> DestinationResolution? {
        guard let city = city(matching: query), let coordinate = city.coord else { return nil }
        let center = Coordinate(latitude: coordinate.lat, longitude: coordinate.lng)
        return DestinationResolution(
            title: city.city,
            coordinate: center,
            region: MKCoordinateRegion(
                center: center.clLocationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.34, longitudeDelta: 0.34)
            )
        )
    }

    func places(for destination: String) -> [TravelPlace] {
        guard let city = city(matching: destination) else { return [] }
        return city.places.enumerated().compactMap { index, place in
            guard let coordinate = place.coord else { return nil }
            let interest = interest(for: place.category)
            return TravelPlace(
                name: place.name,
                address: ([city.city] + place.tags.prefix(2)).joined(separator: " · "),
                coordinate: Coordinate(latitude: coordinate.lat, longitude: coordinate.lng),
                interest: interest,
                source: "AnyTravel 目的地资料（非实时）",
                openingHoursWeek: place.openingHoursWeek,
                popularity: AttractionPopularity(
                    score: max(80, 1_000 - Double(index * 28)),
                    rank: index + 1,
                    evidence: [place.tier == "必去" ? "代表性主游览点" : "公开资料热度排序"]
                ),
                planningPriority: place.tier == "必去" ? .primary : .supplemental
            )
        }
    }

    private func city(matching value: String) -> GuideCity? {
        let needle = Self.normalizedCity(value)
        return cities.first { Self.normalizedCity($0.city) == needle }
    }

    private func interest(for category: String) -> TripInterest {
        switch category {
        case "博物馆", "美术馆", "科技馆", "剧院": .culture
        case "自然", "山水", "海滨", "公园": .nature
        case "亲子", "乐园", "动物园": .family
        case "美食", "美食街": .food
        case "夜游", "夜景": .night
        default: .gardens
        }
    }

    private static func normalizedCity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(
                of: #"(市|省|自治区|特别行政区)$"#,
                with: "",
                options: .regularExpression
            )
    }
}

private struct GuideDocument: Decodable {
    let cities: [GuideCity]
}

private struct GuideCity: Decodable {
    let city: String
    let coord: GuideCoordinate?
    let places: [GuidePlace]
}

private struct GuidePlace: Decodable {
    let name: String
    let coord: GuideCoordinate?
    let category: String
    let tier: String
    let openingHoursWeek: String?
    let tags: [String]

    private enum CodingKeys: String, CodingKey {
        case name, coord, category, tier, openingHoursWeek, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        coord = try container.decodeIfPresent(GuideCoordinate.self, forKey: .coord)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "古迹"
        tier = try container.decodeIfPresent(String.self, forKey: .tier) ?? "推荐"
        openingHoursWeek = try container.decodeIfPresent(String.self, forKey: .openingHoursWeek)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

private struct GuideCoordinate: Decodable {
    let lat: Double
    let lng: Double
}
