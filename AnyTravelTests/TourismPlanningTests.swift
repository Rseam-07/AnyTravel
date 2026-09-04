import XCTest
@testable import AnyTravel

@MainActor
final class TourismPlanningTests: XCTestCase {
    func testRoutePlannerKeepsNearbyPlacesOnTheSameDay() {
        let westA = place("西片一", latitude: 31.300, longitude: 120.600, interest: .culture)
        let westB = place("西片二", latitude: 31.305, longitude: 120.606, interest: .gardens)
        let eastA = place("东片一", latitude: 31.300, longitude: 121.000, interest: .culture)
        let eastB = place("东片二", latitude: 31.306, longitude: 121.006, interest: .nature)
        let draft = TripDraft(destination: "测试城", dayCount: 2, pace: .relaxed)

        let days = RoutePlanner().orderPlaces(
            [westA, eastA, westB, eastB],
            from: Coordinate(latitude: 31.30, longitude: 120.80),
            draft: draft
        )

        XCTAssertEqual(days.count, 2)
        let dayPrefixes = days.map { Set($0.stops.map { String($0.name.prefix(1)) }) }
        XCTAssertTrue(dayPrefixes.contains(Set(["西"])))
        XCTAssertTrue(dayPrefixes.contains(Set(["东"])))
    }

    func testRoutePlannerPlacesMealAfterAVisitAndNightActivityLast() {
        let places = [
            place("夜游", latitude: 31.302, longitude: 120.602, interest: .night),
            place("午餐", latitude: 31.301, longitude: 120.601, interest: .food),
            place("博物馆", latitude: 31.300, longitude: 120.600, interest: .culture)
        ]
        let draft = TripDraft(destination: "测试城", dayCount: 1, pace: .balanced)

        let stops = RoutePlanner().orderPlaces(
            places,
            from: Coordinate(latitude: 31.3, longitude: 120.6),
            draft: draft
        )[0].stops

        XCTAssertEqual(stops.map(\.interest), [.culture, .food, .night])
    }

    func testRoutePlannerRemovesTheSameVenueReturnedByMultipleSources() {
        let sparseMuseum = TravelPlace(
            name: "天津博物馆",
            address: "天津市河西区",
            coordinate: Coordinate(latitude: 39.08475, longitude: 117.22492),
            interest: .culture,
            source: "Apple Maps"
        )
        let detailedMuseum = TravelPlace(
            name: "天津博物馆（文化中心馆区）",
            address: "天津市河西区平江道62号",
            coordinate: Coordinate(latitude: 39.08480, longitude: 117.22498),
            interest: .culture,
            source: "高德地图",
            openingHoursToday: "09:00-16:30"
        )
        let nearbyLibrary = place(
            "天津图书馆",
            latitude: 39.08310,
            longitude: 117.22250,
            interest: .culture
        )

        let days = RoutePlanner().orderPlaces(
            [sparseMuseum, nearbyLibrary, detailedMuseum],
            from: Coordinate(latitude: 39.0842, longitude: 117.2240),
            draft: TripDraft(destination: "天津市", dayCount: 1)
        )
        let stops = days.flatMap(\.stops)

        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops.filter { $0.name.contains("天津博物馆") }.count, 1)
        XCTAssertEqual(stops.first(where: { $0.name.contains("天津博物馆") })?.source, "高德地图")
    }

    func testRoutePlannerKeepsSameNamedBranchesThatAreFarApart() {
        let downtown = place("城市书房", latitude: 39.084, longitude: 117.225, interest: .culture)
        let riverside = place("城市书房", latitude: 39.084, longitude: 117.245, interest: .culture)

        let stops = RoutePlanner().orderPlaces(
            [downtown, riverside],
            from: Coordinate(latitude: 39.084, longitude: 117.235),
            draft: TripDraft(destination: "天津市", dayCount: 1)
        ).flatMap(\.stops)

        XCTAssertEqual(stops.count, 2)
    }

    func testPrimarySelectedAttractionGetsLongerVisitThanSupplement() {
        let primary = TravelPlace(
            name: "主游览点",
            address: "测试地址",
            coordinate: Coordinate(latitude: 31.30, longitude: 120.60),
            interest: .culture,
            planningPriority: .primary
        )
        let supplemental = TravelPlace(
            name: "顺路补充点",
            address: "测试地址",
            coordinate: Coordinate(latitude: 31.31, longitude: 120.61),
            interest: .culture,
            planningPriority: .supplemental
        )
        let policy = TourismPlanningPolicy()

        XCTAssertGreaterThan(
            policy.visitMinutes(for: primary, pace: .relaxed),
            policy.visitMinutes(for: supplemental, pace: .relaxed)
        )
    }

    func testPlannerPanelMetricsHaveThreeOrderedDetentsAndSnapToTheClosestOne() {
        let metrics = PlannerPanelLayout.metrics(containerHeight: 844, safeAreaTop: 59)

        XCTAssertLessThan(metrics.compact, metrics.medium)
        XCTAssertLessThan(metrics.medium, metrics.expanded)
        XCTAssertEqual(metrics.closestDetent(to: metrics.compact + 4), .compact)
        XCTAssertEqual(metrics.closestDetent(to: metrics.medium - 3), .medium)
        XCTAssertEqual(metrics.closestDetent(to: metrics.expanded - 5), .expanded)
        XCTAssertGreaterThan(metrics.expanded, 700)
    }

    func testFoodStopCarriesLunchWithoutDuplicateGenericMeal() {
        let day = ItineraryDay(index: 0, stops: [
            place("博物馆", latitude: 31.300, longitude: 120.600, interest: .culture),
            place("本地午餐", latitude: 31.302, longitude: 120.602, interest: .food)
        ])

        let schedule = ScheduleBuilder().build(
            for: day,
            pace: .relaxed,
            accommodation: nil,
            travelMode: .walking
        )

        XCTAssertFalse(schedule.contains { $0.title == "午餐与休息" })
        XCTAssertTrue(schedule.first(where: { $0.title == "本地午餐" })?.detail.contains("兼作正餐") == true)
        XCTAssertTrue(schedule.contains { $0.title == "前往本地午餐" })
    }

    func testScheduleKeepsEverySelectedStopEvenWhenTheDayIsOverCapacity() {
        let day = ItineraryDay(index: 0, stops: [
            place("博物馆", latitude: 31.300, longitude: 120.600, interest: .culture),
            place("园林甲", latitude: 31.302, longitude: 120.602, interest: .gardens),
            place("园林乙", latitude: 31.304, longitude: 120.604, interest: .gardens),
            place("夜游", latitude: 31.306, longitude: 120.606, interest: .night)
        ])

        let schedule = ScheduleBuilder().build(for: day, pace: .relaxed, accommodation: nil)
        let scheduledPlaceIDs = Set(schedule.compactMap(\.placeID))

        XCTAssertEqual(scheduledPlaceIDs, Set(day.stops.map(\.id)))
    }

    func testNightActivityStartsAfterTheNightWindowAndIncludesRest() throws {
        let day = ItineraryDay(index: 0, stops: [
            place("园林", latitude: 31.300, longitude: 120.600, interest: .gardens),
            place("夜游", latitude: 31.301, longitude: 120.601, interest: .night)
        ])

        let schedule = ScheduleBuilder().build(for: day, pace: .relaxed, accommodation: nil)
        let night = try XCTUnwrap(schedule.first { $0.title == "夜游" })

        XCTAssertTrue(night.timeText.hasPrefix("18:30"))
        XCTAssertTrue(schedule.contains { $0.title == "午后留白与晚餐" })
        XCTAssertTrue(schedule.contains { $0.title == "午餐与休息" })
    }

    func testFamilyHeavyDayIsReportedAsOverCapacity() {
        let day = ItineraryDay(index: 0, stops: [
            place("亲子馆一", latitude: 31.300, longitude: 120.600, interest: .family),
            place("亲子馆二", latitude: 31.310, longitude: 120.610, interest: .family)
        ])

        let assessment = TourismDayAssessmentService().assess(
            day: day,
            pace: .relaxed,
            mode: .transit,
            actualTravelMinutes: 35
        )

        XCTAssertTrue(assessment.isOverCapacity)
        XCTAssertTrue(assessment.detail.contains("减一站或增加一天"))
    }

    func testOpeningHoursDelayAVisitInsteadOfPretendingTheVenueIsOpen() throws {
        let day = ItineraryDay(index: 0, stops: [
            TravelPlace(
                name: "午后展馆",
                address: "测试地址",
                coordinate: Coordinate(latitude: 31.300, longitude: 120.600),
                interest: .culture,
                openingHoursToday: "13:00-17:00"
            )
        ])

        let schedule = ScheduleBuilder().build(for: day, pace: .relaxed, accommodation: nil)
        let visit = try XCTUnwrap(schedule.first { $0.title == "午后展馆" })

        XCTAssertTrue(schedule.contains { $0.title == "等候开门与附近慢逛" })
        XCTAssertEqual(visit.timeText, "13:00–15:15")
        XCTAssertTrue(visit.detail.contains("今日营业13:00–17:00"))
    }

    func testWeeklyOpeningHoursUseThePlannedWeekday() throws {
        let tuesday = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 8)))
        let venue = TravelPlace(
            name: "每周一休息的展馆",
            address: "测试地址",
            coordinate: Coordinate(latitude: 31.300, longitude: 120.600),
            interest: .culture,
            openingHoursWeek: "Mo off; Tu-Su 09:00-17:00"
        )

        let state = TourismPlanningPolicy().openingState(for: venue, on: tuesday)

        XCTAssertEqual(state, .open(.init(startMinute: 9 * 60, endMinute: 17 * 60)))
    }

    func testRoutePlannerMovesRegularMondayClosureToAnotherDay() throws {
        let monday = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 7)))
        let museum = place("苏州博物馆", latitude: 31.325, longitude: 120.621, interest: .culture)
        let garden = place("金鸡湖", latitude: 31.316, longitude: 120.680, interest: .nature)
        let draft = TripDraft(
            destination: "苏州",
            dayCount: 2,
            logistics: TripLogistics(startDate: monday)
        )

        let days = RoutePlanner().orderPlaces(
            [museum, garden],
            from: museum.coordinate,
            draft: draft
        )

        XCTAssertFalse(days[0].stops.contains { $0.name == "苏州博物馆" })
        XCTAssertTrue(days[1].stops.contains { $0.name == "苏州博物馆" })
    }

    func testArrivalConstraintMovesTheFirstVisitAndExplainsTheBuffer() throws {
        let day = ItineraryDay(index: 0, stops: [
            place("园林", latitude: 31.300, longitude: 120.600, interest: .gardens)
        ])
        let constraints = TourismDayConstraints(
            earliestStartMinute: 14 * 60,
            startNote: "抵达后先接驳和安顿"
        )

        let schedule = ScheduleBuilder().build(
            for: day,
            pace: .relaxed,
            accommodation: nil,
            constraints: constraints
        )
        let visit = try XCTUnwrap(schedule.first { $0.title == "园林" })

        XCTAssertEqual(schedule.first?.title, "抵达、接驳与安顿")
        XCTAssertEqual(visit.timeText, "15:30–17:30")
        XCTAssertTrue(schedule.first?.detail.contains("先接驳和安顿") == true)
    }

    func testReturnConstraintFlagsAPlanThatEndsAfterTheLeaveByTime() {
        let day = ItineraryDay(index: 0, stops: [
            place("园林", latitude: 31.300, longitude: 120.600, interest: .gardens),
            place("博物馆", latitude: 31.301, longitude: 120.601, interest: .culture)
        ])
        let constraints = TourismDayConstraints(
            latestEndMinute: 15 * 60,
            endNote: "为返程高铁留出进站时间"
        )

        let schedule = ScheduleBuilder().build(
            for: day,
            pace: .relaxed,
            accommodation: nil,
            constraints: constraints
        )

        XCTAssertTrue(schedule.contains { $0.title == "返程前需要调整" })
        XCTAssertTrue(schedule.contains { $0.timeText == "需在15:00前" })
        XCTAssertFalse(schedule.contains { $0.title == "离开游览区，前往返程枢纽" })
    }

    private func place(
        _ name: String,
        latitude: Double,
        longitude: Double,
        interest: TripInterest
    ) -> TravelPlace {
        TravelPlace(
            name: name,
            address: "测试地址",
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            interest: interest
        )
    }
}
