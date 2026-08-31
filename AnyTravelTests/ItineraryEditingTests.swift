import XCTest
@testable import AnyTravel

final class ItineraryEditingTests: XCTestCase {
    @MainActor
    func testCanAddReorderAndRemoveStopsWithoutRegeneratingThePlan() throws {
        let model = try makeModel()
        let first = place("拙政园", latitude: 31.3265)
        let second = place("苏州博物馆", latitude: 31.3247)
        let added = place("平江路", latitude: 31.3150)
        model.itineraryDays = [ItineraryDay(index: 0, stops: [first, second])]
        model.selectedDayIndex = 0

        XCTAssertTrue(model.addPlace(added, to: 0, refreshRoute: false))
        XCTAssertEqual(model.currentStops.map(\.name), ["拙政园", "苏州博物馆", "平江路"])
        XCTAssertEqual(model.selectedPlaceID, added.id)

        model.movePlace(added, by: -1, in: 0, refreshRoute: false)
        XCTAssertEqual(model.currentStops.map(\.name), ["拙政园", "平江路", "苏州博物馆"])

        XCTAssertTrue(model.removePlace(first, from: 0, refreshRoute: false))
        XCTAssertEqual(model.currentStops.map(\.name), ["平江路", "苏州博物馆"])
        guard case .stale = model.quoteRefreshState else {
            return XCTFail("编辑景点后应该标记住宿与交通结果需要重算")
        }
    }

    @MainActor
    func testDoesNotDuplicateAPlaceOrLeaveADayEmpty() throws {
        let model = try makeModel()
        let first = place("拙政园", latitude: 31.3265)
        let duplicate = place("拙政园", latitude: 31.3266)
        model.itineraryDays = [ItineraryDay(index: 0, stops: [first])]

        XCTAssertFalse(model.addPlace(duplicate, to: 0, refreshRoute: false))
        XCTAssertEqual(model.currentStops.count, 1)
        XCTAssertFalse(model.removePlace(first, from: 0, refreshRoute: false))
        XCTAssertEqual(model.currentStops.count, 1)
        XCTAssertTrue(model.noticeMessage?.contains("至少留下一处") == true)
    }

    @MainActor
    private func makeModel() throws -> PlannerViewModel {
        let suiteName = "AnyTravel.ItineraryEditingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnyTravel-ItineraryEditingTests-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return PlannerViewModel(
            preferencesStore: PlannerPreferencesStore(defaults: defaults),
            tripStore: TripStore(fileURL: fileURL)
        )
    }

    @MainActor
    private func place(_ name: String, latitude: Double) -> TravelPlace {
        TravelPlace(
            name: name,
            address: "苏州市姑苏区",
            coordinate: Coordinate(latitude: latitude, longitude: 120.6250),
            interest: .culture
        )
    }
}
