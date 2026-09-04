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

        XCTAssertEqual(lines.first(where: { $0.id == "outbound-transport" })?.amountCNY, 80)
        XCTAssertEqual(lines.first(where: { $0.id == "return-transport" })?.amountCNY, 80)
        XCTAssertEqual(lines.first(where: { $0.id == "accommodation" })?.amountCNY, 1_000)
        XCTAssertEqual(lines.first(where: { $0.id == "outbound-transport" })?.source, .live)
        XCTAssertEqual(lines.first(where: { $0.id == "return-transport" })?.source, .budgetEnvelope)
        XCTAssertTrue(lines.first(where: { $0.id == "return-transport" })?.detail.contains("尚非返程实时报价") == true)
    }

    @MainActor
    func testReturnLiveQuoteReplacesMirroredOutboundEstimate() {
        var logistics = TripLogistics()
        logistics.travelers = 2
        let draft = TripDraft(destination: "苏州", budgetPerPerson: 3_000, logistics: logistics)
        let outbound = TransportOption(
            mode: .train,
            title: "G7001 · 上海→苏州",
            originName: "上海",
            destinationName: "苏州",
            quotes: [ProviderQuote(provider: .railway12306, amountCNY: 40, unit: .perPerson, kind: .live, note: "去程")]
        )
        let returnTrip = TransportOption(
            mode: .train,
            title: "G7028 · 苏州→上海",
            originName: "苏州",
            destinationName: "上海",
            direction: .returnTrip,
            quotes: [ProviderQuote(provider: .railway12306, amountCNY: 50, unit: .perPerson, kind: .live, note: "返程")]
        )

        let lines = ExpensePlanner().buildLines(
            draft: draft,
            accommodation: nil,
            transport: outbound,
            returnTransport: returnTrip
        )
        let returnLine = lines.first(where: { $0.id == "return-transport" })

        XCTAssertEqual(returnLine?.amountCNY, 100)
        XCTAssertEqual(returnLine?.source, .live)
        XCTAssertTrue(returnLine?.detail.contains("当前返程") == true)
        XCTAssertFalse(returnLine?.detail.contains("按当前去程价格预留") == true)
    }

    @MainActor
    func testSelectedTransfersBecomeExplicitExpensesWithoutDoubleCountingTheLocalEnvelope() {
        var logistics = TripLogistics()
        logistics.travelers = 2
        let draft = TripDraft(destination: "苏州", budgetPerPerson: 3_000, logistics: logistics)
        let outboundTransfer = LocalTransferOption(
            direction: .outbound,
            mode: .publicTransit,
            originName: "苏州站",
            destinationName: "测试酒店",
            durationMinutes: 26,
            distanceMeters: 5_200,
            estimatedCostCNY: 8,
            costNote: "按 2 人估算"
        )
        let returnTransfer = LocalTransferOption(
            direction: .returnTrip,
            mode: .taxi,
            originName: "测试酒店",
            destinationName: "苏州站",
            durationMinutes: 18,
            distanceMeters: 6_100,
            estimatedCostCNY: 28,
            costNote: "按里程估算"
        )

        let lines = ExpensePlanner().buildLines(
            draft: draft,
            accommodation: nil,
            transport: nil,
            outboundTransfer: outboundTransfer,
            returnTransfer: returnTransfer
        )

        XCTAssertEqual(lines.first(where: { $0.id == "outbound-transfer" })?.amountCNY, 8)
        XCTAssertEqual(lines.first(where: { $0.id == "return-transfer" })?.amountCNY, 28)
        XCTAssertEqual(lines.first(where: { $0.id == "outbound-transfer" })?.source, .estimate)
        XCTAssertEqual(lines.first(where: { $0.id == "local" })?.amountCNY, 384)
        XCTAssertTrue(lines.first(where: { $0.id == "local" })?.detail.contains("扣除已选往返接驳") == true)
    }

    @MainActor
    func testTransferPolicyAccountsForPartySizeAndLateArrival() {
        let policy = LocalTransferPolicy()
        XCTAssertEqual(
            policy.estimatedCost(for: .publicTransit, distanceMeters: 5_200, durationMinutes: 26, travelers: 3),
            6
        )
        XCTAssertEqual(
            policy.estimatedCost(for: .taxi, distanceMeters: 5_200, durationMinutes: 20, travelers: 3),
            25
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lateArrival = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23))
        let options = [
            LocalTransferOption(
                direction: .outbound,
                mode: .publicTransit,
                originName: "车站",
                destinationName: "酒店",
                durationMinutes: 34,
                distanceMeters: 6_000,
                estimatedCostCNY: 6,
                costNote: "估算"
            ),
            LocalTransferOption(
                direction: .outbound,
                mode: .taxi,
                originName: "车站",
                destinationName: "酒店",
                durationMinutes: 18,
                distanceMeters: 6_500,
                estimatedCostCNY: 29,
                costNote: "估算"
            )
        ]

        XCTAssertEqual(
            policy.recommendedMode(from: options, referenceDate: lateArrival, travelers: 1, calendar: calendar),
            .taxi
        )
    }

    @MainActor
    func testTransferPolicyDoesNotPresentDistanceEstimateAsLiveTransitRecommendation() {
        let options = [
            LocalTransferOption(
                direction: .outbound,
                mode: .publicTransit,
                originName: "车站",
                destinationName: "酒店",
                durationMinutes: 30,
                distanceMeters: 6_000,
                estimatedCostCNY: 4,
                routeKind: .distanceEstimate,
                costNote: "距离估算"
            ),
            LocalTransferOption(
                direction: .outbound,
                mode: .taxi,
                originName: "车站",
                destinationName: "酒店",
                durationMinutes: 18,
                distanceMeters: 6_500,
                estimatedCostCNY: 29,
                routeKind: .appleMaps,
                costNote: "地图路线"
            )
        ]

        XCTAssertEqual(
            LocalTransferPolicy().recommendedMode(from: options, referenceDate: nil, travelers: 1),
            .taxi
        )
    }

    @MainActor
    func testSkippingTransportDoesNotInventATransportExpense() {
        var logistics = TripLogistics()
        logistics.skipTransport = true
        let draft = TripDraft(destination: "苏州", budgetPerPerson: 3_000, logistics: logistics)

        let lines = ExpensePlanner().buildLines(draft: draft, accommodation: nil, transport: nil)

        XCTAssertEqual(lines.first(where: { $0.id == "transport" })?.amountCNY, 0)
        XCTAssertEqual(lines.first(where: { $0.id == "transport" })?.detail, "已按你的选择暂时跳过")
    }

    @MainActor
    func testLiveTicketQuotesReplaceTheTicketBudgetEnvelope() {
        var logistics = TripLogistics()
        logistics.travelers = 2
        let draft = TripDraft(destination: "苏州", budgetPerPerson: 3_000, logistics: logistics)
        let quotedPlace = TravelPlace(
            name: "拙政园",
            address: "东北街178号",
            coordinate: Coordinate(latitude: 31.326, longitude: 120.629),
            interest: .gardens,
            ticketQuote: ProviderQuote(
                provider: .qunar,
                amountCNY: 80,
                unit: .perPerson,
                kind: .live,
                note: "当前展示起价"
            )
        )
        let day = ItineraryDay(index: 0, stops: [quotedPlace])

        let lines = ExpensePlanner().buildLines(
            draft: draft,
            accommodation: nil,
            transport: nil,
            itineraryDays: [day]
        )
        let ticketLine = lines.first(where: { $0.id == "tickets" })

        XCTAssertEqual(ticketLine?.amountCNY, 160)
        XCTAssertEqual(ticketLine?.source, .live)
        XCTAssertTrue(ticketLine?.detail.contains("1处采用渠道当前展示价") == true)
        XCTAssertTrue(
            ScheduleBuilder().build(for: day, pace: .relaxed, accommodation: nil)
                .first(where: { $0.placeID == quotedPlace.id })?.detail.contains("去哪儿¥80/人") == true
        )
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
        XCTAssertTrue(restored.logistics.hasDates)
        XCTAssertEqual(
            Calendar.current.dateComponents(
                [.day],
                from: try XCTUnwrap(restored.logistics.startDate),
                to: try XCTUnwrap(restored.logistics.endDate)
            ).day,
            2
        )
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
