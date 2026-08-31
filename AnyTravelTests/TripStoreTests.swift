import XCTest
@testable import AnyTravel

final class TripStoreTests: XCTestCase {
    @MainActor
    func testPersistsAndReloadsATrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("trips.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let draft = TripDraft(destination: "苏州")
        let stop = TravelPlace(
            name: "拙政园",
            address: "江苏省苏州市姑苏区东北街178号",
            coordinate: Coordinate(latitude: 31.3265, longitude: 120.6251),
            interest: .gardens
        )
        let trip = SavedTrip(
            title: "苏州 · 1天",
            createdAt: Date(timeIntervalSince1970: 2_000_000_000),
            draft: draft,
            destinationCenter: Coordinate(latitude: 31.2989, longitude: 120.5853),
            days: [ItineraryDay(index: 0, stops: [stop])]
        )

        let writer = TripStore(fileURL: fileURL)
        try writer.save(trip)

        let reader = TripStore(fileURL: fileURL)
        XCTAssertEqual(reader.trips, [trip])
        XCTAssertNil(reader.lastErrorMessage)
    }

    @MainActor
    func testDeletePersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("trips.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let trip = SavedTrip(
            title: "杭州 · 1天",
            draft: TripDraft(destination: "杭州", dayCount: 1),
            destinationCenter: Coordinate(latitude: 30.2741, longitude: 120.1551),
            days: []
        )
        let store = TripStore(fileURL: fileURL)
        try store.save(trip)
        try store.delete(trip)

        XCTAssertTrue(TripStore(fileURL: fileURL).trips.isEmpty)
    }

    @MainActor
    func testFailedWriteDoesNotLeaveAPhantomSavedTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blockingFile)
        let impossibleURL = blockingFile.appendingPathComponent("trips.json")
        let store = TripStore(fileURL: impossibleURL)
        let trip = SavedTrip(
            title: "南京 · 1天",
            draft: TripDraft(destination: "南京", dayCount: 1),
            destinationCenter: Coordinate(latitude: 32.0603, longitude: 118.7969),
            days: []
        )

        XCTAssertThrowsError(try store.save(trip))
        XCTAssertTrue(store.trips.isEmpty)
        XCTAssertNotNil(store.lastErrorMessage)
    }
}
