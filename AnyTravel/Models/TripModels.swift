import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum TripInterest: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case gardens
    case culture
    case food
    case nature
    case family
    case night

    var id: Self { self }

    var title: String {
        switch self {
        case .gardens: "园林建筑"
        case .culture: "人文博物馆"
        case .food: "本地美食"
        case .nature: "自然慢逛"
        case .family: "亲子体验"
        case .night: "夜间活动"
        }
    }

    var symbolName: String {
        switch self {
        case .gardens: "building.columns"
        case .culture: "building.columns.fill"
        case .food: "fork.knife"
        case .nature: "leaf"
        case .family: "figure.2.and.child.holdinghands"
        case .night: "moon.stars"
        }
    }

    var searchTerm: String {
        switch self {
        case .gardens: "园林 景点"
        case .culture: "博物馆 人文景点"
        case .food: "本地餐厅"
        case .nature: "公园 自然景点"
        case .family: "亲子景点"
        case .night: "夜游 夜间景点"
        }
    }
}

enum TripPace: String, CaseIterable, Codable, Identifiable, Sendable {
    case relaxed
    case balanced
    case full

    var id: Self { self }

    var title: String {
        switch self {
        case .relaxed: "松弛"
        case .balanced: "适中"
        case .full: "充实"
        }
    }

    var stopsPerDay: Int {
        switch self {
        case .relaxed: 2
        case .balanced: 3
        case .full: 4
        }
    }
}

enum TravelMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case walking
    case transit
    case driving

    var id: Self { self }

    var title: String {
        switch self {
        case .walking: "步行优先"
        case .transit: "公交优先"
        case .driving: "驾车"
        }
    }

    var symbolName: String {
        switch self {
        case .walking: "figure.walk"
        case .transit: "bus"
        case .driving: "car"
        }
    }

    var mapKitType: MKDirectionsTransportType {
        switch self {
        case .walking: .walking
        case .transit: .transit
        case .driving: .automobile
        }
    }
}

struct TripDraft: Codable, Equatable, Hashable, Sendable {
    var destination = ""
    var dayCount = 3
    var budgetPerPerson = 3_000
    var interests: Set<TripInterest> = [.gardens, .culture, .food]
    var pace: TripPace = .relaxed
    var travelMode: TravelMode = .walking
    var logistics = TripLogistics()

    init(
        destination: String = "",
        dayCount: Int = 3,
        budgetPerPerson: Int = 3_000,
        interests: Set<TripInterest> = [.gardens, .culture, .food],
        pace: TripPace = .relaxed,
        travelMode: TravelMode = .walking,
        logistics: TripLogistics = TripLogistics()
    ) {
        self.destination = destination
        self.dayCount = dayCount
        self.budgetPerPerson = budgetPerPerson
        self.interests = interests
        self.pace = pace
        self.travelMode = travelMode
        self.logistics = logistics
    }

    private enum CodingKeys: String, CodingKey {
        case destination
        case dayCount
        case budgetPerPerson
        case interests
        case pace
        case travelMode
        case logistics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
        dayCount = try container.decodeIfPresent(Int.self, forKey: .dayCount) ?? 3
        budgetPerPerson = try container.decodeIfPresent(Int.self, forKey: .budgetPerPerson) ?? 3_000
        interests = try container.decodeIfPresent(Set<TripInterest>.self, forKey: .interests)
            ?? [.gardens, .culture, .food]
        pace = try container.decodeIfPresent(TripPace.self, forKey: .pace) ?? .relaxed
        travelMode = try container.decodeIfPresent(TravelMode.self, forKey: .travelMode) ?? .walking
        logistics = try container.decodeIfPresent(TripLogistics.self, forKey: .logistics) ?? TripLogistics()
    }

    var summary: String {
        "\(dayCount)天 · 约¥\(budgetPerPerson)/人 · \(pace.title)"
    }
}

struct TravelPlace: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let coordinate: Coordinate
    let interest: TripInterest
    let source: String

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        coordinate: Coordinate,
        interest: TripInterest,
        source: String = "Apple Maps"
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.interest = interest
        self.source = source
    }
}

struct ItineraryDay: Codable, Hashable, Identifiable, Sendable {
    let index: Int
    var stops: [TravelPlace]

    var id: Int { index }
    var title: String { "第 \(index + 1) 天" }
}

struct SavedTrip: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var draft: TripDraft
    var destinationCenter: Coordinate
    var days: [ItineraryDay]
    var logisticsSnapshot: LogisticsSnapshot?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        draft: TripDraft,
        destinationCenter: Coordinate,
        days: [ItineraryDay],
        logisticsSnapshot: LogisticsSnapshot? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.draft = draft
        self.destinationCenter = destinationCenter
        self.days = days
        self.logisticsSnapshot = logisticsSnapshot
    }
}

struct DestinationResolution: Sendable {
    let title: String
    let coordinate: Coordinate
    let region: MKCoordinateRegion
}

struct PlannedLeg: Identifiable {
    let id = UUID()
    let dayIndex: Int
    let sourceID: TravelPlace.ID
    let destinationID: TravelPlace.ID
    let route: MKRoute
}

struct RouteBuildResult {
    var legs: [PlannedLeg]
    var failedSegments: Int
}

enum PlannerPhase: Equatable {
    case destination
    case preferences
    case discovering
    case ready
    case failure
}

enum MapAppearance: String, CaseIterable, Identifiable {
    case standard
    case imagery
    case hybrid

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "标准"
        case .imagery: "卫星"
        case .hybrid: "混合"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "map"
        case .imagery: "globe.americas"
        case .hybrid: "square.3.layers.3d"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .all)
        case .imagery: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .all)
        }
    }
}

enum PlanningError: LocalizedError {
    case emptyDestination
    case destinationNotFound
    case placesNotFound
    case routeUnavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyDestination: "先输入一个城市或目的地。"
        case .destinationNotFound: "没有找到这个目的地，请换一种写法后重试。"
        case .placesNotFound: "附近暂时没有找到足够的匹配地点，可以减少偏好后重试。"
        case .routeUnavailable: "Apple Maps 暂时没有返回这一天的可用路线。"
        case .saveFailed: "行程暂时无法保存，请稍后再试。"
        }
    }
}
