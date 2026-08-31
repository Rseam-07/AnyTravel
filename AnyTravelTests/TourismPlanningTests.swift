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
