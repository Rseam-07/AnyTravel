import MapKit
import XCTest
@testable import AnyTravel

final class CompletePlanTests: XCTestCase {
    @MainActor
    func testNewAndMigratedDraftsDefaultToRelaxedPace() throws {
        XCTAssertEqual(TripDraft().pace, .relaxed)

        let oldPayload = Data(#"{"destination":"苏州","dayCount":2,"budgetPerPerson":4000}"#.utf8)
        let migrated = try JSONDecoder().decode(TripDraft.self, from: oldPayload)

        XCTAssertEqual(migrated.destination, "苏州")
        XCTAssertEqual(migrated.pace, .relaxed)
        XCTAssertEqual(migrated.logistics, TripLogistics())
    }

    @MainActor
    func testExplicitTransportChoiceOverridesDistanceRecommendation() {
        var logistics = TripLogistics()
        logistics.origin = "远方"
        logistics.preferredLongDistanceMode = .train
        let draft = TripDraft(destination: "目的地", logistics: logistics)
        let origin = resolution("远方", latitude: 20, longitude: 110)
        let destination = resolution("目的地", latitude: 31, longitude: 120)

        let options = TransportRecommendationEngine().buildOptions(
            origin: origin,
            destination: destination,
            accessPoints: [],
            selectedAccommodation: nil,
            draft: draft
        )

        XCTAssertEqual(options.first?.mode, .train)
        XCTAssertEqual(options.first?.isRecommended, true)
    }

    @MainActor
    func testLiveQuotesFlowIntoDetailedExpenseTable() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var logistics = TripLogistics()
        logistics.travelers = 2
        logistics.startDate = start
        logistics.endDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 2, to: start)
        let draft = TripDraft(destination: "苏州", budgetPerPerson: 3_000, logistics: logistics)
        let hotel = AccommodationOption(
            name: "测试酒店",
            address: "苏州",
            coordinate: Coordinate(latitude: 31.3, longitude: 120.6),
            attractionDistanceMeters: 500,
            quotes: [ProviderQuote(provider: .ctrip, amountCNY: 500, unit: .perNight, kind: .live, note: "测试")]
        )
        let train = TransportOption(
            mode: .train,
            title: "高铁抵达苏州",
            originName: "上海",
            destinationName: "苏州",
            quotes: [ProviderQuote(provider: .railway12306, amountCNY: 40, unit: .perPerson, kind: .live, note: "测试")]
        )

        let lines = ExpensePlanner().buildLines(draft: draft, accommodation: hotel, transport: train)

        XCTAssertEqual(lines.first(where: { $0.id == "transport" })?.amountCNY, 80)
        XCTAssertEqual(lines.first(where: { $0.id == "accommodation" })?.amountCNY, 1_000)
        XCTAssertEqual(lines.first(where: { $0.id == "transport" })?.source, .live)
    }

    @MainActor
    func testRelaxedScheduleStartsLateAndKeepsTwoStops() {
        let day = ItineraryDay(index: 0, stops: [
            place("拙政园", interest: .gardens),
            place("苏州博物馆", interest: .culture)
        ])

        let schedule = ScheduleBuilder().build(for: day, pace: .relaxed, accommodation: nil)

        XCTAssertEqual(schedule.first?.timeText, "10:00–12:00")
        XCTAssertEqual(schedule.filter { $0.placeID != nil }.count, 2)
        XCTAssertTrue(schedule.contains { $0.title == "午餐与休息" })
    }

    @MainActor
    func testInitialPreferencesPersistAndAreAppliedToANewDraft() throws {
        let suiteName = "AnyTravelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlannerPreferencesStore(defaults: defaults)
        var logistics = TripLogistics()
        logistics.origin = "上海"
        logistics.travelers = 3
        let draft = TripDraft(budgetPerPerson: 7_500, pace: .balanced, logistics: logistics)

        store.save(from: draft)
        let restored = store.applyingSavedPreferences()

        XCTAssertEqual(restored.logistics.origin, "上海")
        XCTAssertEqual(restored.logistics.travelers, 3)
        XCTAssertEqual(restored.budgetPerPerson, 7_500)
        XCTAssertEqual(restored.pace, .relaxed)
    }

    @MainActor
    private func resolution(_ title: String, latitude: Double, longitude: Double) -> DestinationResolution {
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        return DestinationResolution(
            title: title,
            coordinate: coordinate,
            region: MKCoordinateRegion(
                center: coordinate.clLocationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        )
    }

    @MainActor
    private func place(_ name: String, interest: TripInterest) -> TravelPlace {
        TravelPlace(
            name: name,
            address: "苏州",
            coordinate: Coordinate(latitude: 31.3, longitude: 120.6),
            interest: interest
        )
    }
}
