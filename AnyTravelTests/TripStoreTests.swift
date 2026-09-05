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
    func testPersistsSelectedDoorToDoorTransfers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("trips.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let outbound = LocalTransferOption(
            direction: .outbound,
            mode: .taxi,
            originName: "苏州站",
            destinationName: "测试酒店",
            durationMinutes: 19,
            distanceMeters: 6_980,
            estimatedCostCNY: 32,
            routeKind: .appleMaps,
            costNote: "地图路线，价格按里程估算"
        )
        let returnTrip = LocalTransferOption(
            direction: .returnTrip,
            mode: .publicTransit,
            originName: "测试酒店",
            destinationName: "苏州站",
            durationMinutes: 32,
            distanceMeters: 6_980,
            estimatedCostCNY: 4,
            routeKind: .distanceEstimate,
            costNote: "公交路线待复核"
        )
        let snapshot = LogisticsSnapshot(
            accommodations: [],
            selectedAccommodationID: nil,
            transportOptions: [],
            selectedTransportID: nil,
            outboundTransferOptions: [outbound],
            selectedOutboundTransferID: outbound.id,
            returnTransferOptions: [returnTrip],
            selectedReturnTransferID: returnTrip.id
        )
        let trip = SavedTrip(
            title: "苏州 · 门到门",
            draft: TripDraft(destination: "苏州"),
            destinationCenter: Coordinate(latitude: 31.2989, longitude: 120.5853),
            days: [],
            logisticsSnapshot: snapshot
        )

        try TripStore(fileURL: fileURL).save(trip)
        let restored = try XCTUnwrap(TripStore(fileURL: fileURL).trips.first?.logisticsSnapshot)
        let restoredOutbound = try XCTUnwrap(restored.outboundTransferOptions?.first)

        XCTAssertEqual(restored.selectedOutboundTransferID, outbound.id)
        XCTAssertEqual(restoredOutbound.id, outbound.id)
        XCTAssertEqual(restoredOutbound.mode, .taxi)
        XCTAssertEqual(restoredOutbound.routeKind, .appleMaps)
        XCTAssertEqual(restoredOutbound.estimatedCostCNY, 32)
        XCTAssertEqual(restored.selectedReturnTransferID, returnTrip.id)
        XCTAssertEqual(restored.returnTransferOptions?.first?.routeKind, .distanceEstimate)
    }

    @MainActor
    func testPersistsUserConfirmedExternalBooking() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("trips.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hotelID = UUID()
        let confirmation = BookingConfirmation(
            id: UUID(),
            kind: .accommodation,
            itemID: hotelID,
            title: "测试酒店",
            confirmedAt: Date(timeIntervalSince1970: 2_000_000_000),
            startDate: Date(timeIntervalSince1970: 2_000_086_400),
            endDate: Date(timeIntervalSince1970: 2_000_259_200),
            actualAmountCNY: 1_688,
            note: "订单尾号 1234"
        )
        let snapshot = LogisticsSnapshot(
            accommodations: [],
            selectedAccommodationID: hotelID,
            transportOptions: [],
            selectedTransportID: nil,
            bookingConfirmations: [confirmation]
        )
        let trip = SavedTrip(
            title: "苏州 · 已订住宿",
            draft: TripDraft(destination: "苏州"),
            destinationCenter: Coordinate(latitude: 31.2989, longitude: 120.5853),
            days: [],
            logisticsSnapshot: snapshot
        )

        try TripStore(fileURL: fileURL).save(trip)
        let restored = try XCTUnwrap(TripStore(fileURL: fileURL).trips.first?.logisticsSnapshot?.bookingConfirmations?.first)

        XCTAssertEqual(restored.itemID, hotelID)
        XCTAssertEqual(restored.note, "订单尾号 1234")
        XCTAssertEqual(restored.actualAmountCNY, 1_688)
        XCTAssertEqual(restored.kind, .accommodation)
    }

    @MainActor
    func testOlderLogisticsSnapshotWithoutBookingFieldStillDecodes() throws {
        let legacy = Data(#"{"accommodations":[],"transportOptions":[]}"#.utf8)

        let restored = try JSONDecoder().decode(LogisticsSnapshot.self, from: legacy)

        XCTAssertNil(restored.bookingConfirmations)
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

    @MainActor
    func testCorruptPrimaryFallsBackToBackupAndPreservesOriginalBeforeNextSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("trips.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SavedTrip(
            title: "苏州 · 旧版本",
            draft: TripDraft(destination: "苏州"),
            destinationCenter: Coordinate(latitude: 31.2989, longitude: 120.5853),
            days: []
        )
        let latest = SavedTrip(
            title: "杭州 · 新版本",
            draft: TripDraft(destination: "杭州"),
            destinationCenter: Coordinate(latitude: 30.2741, longitude: 120.1551),
            days: []
        )
        let writer = TripStore(fileURL: fileURL)
        try writer.save(first)
        try writer.save(latest)
        try Data("{broken".utf8).write(to: fileURL, options: .atomic)

        let recovered = TripStore(fileURL: fileURL)
        XCTAssertEqual(recovered.trips.map(\.id), [first.id])
        XCTAssertEqual(recovered.trips.first?.title, first.title)
        XCTAssertTrue(recovered.lastErrorMessage?.contains("上次备份") == true)
        try recovered.save(latest)

        XCTAssertEqual(TripStore(fileURL: fileURL).trips.first?.title, latest.title)
        XCTAssertEqual(try String(contentsOf: fileURL.appendingPathExtension("unreadable"), encoding: .utf8), "{broken")
    }
}
