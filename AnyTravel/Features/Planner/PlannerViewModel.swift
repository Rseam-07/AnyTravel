import CoreLocation
import MapKit
import Observation
import SwiftUI
import UIKit

@Observable
final class PlannerViewModel {
    enum RecoveryAction {
        case resolveDestination
        case generatePlan
    }

    var draft = TripDraft()
    var phase: PlannerPhase = .destination
    var destination: DestinationResolution?
    var itineraryDays: [ItineraryDay] = []
    var routesByDay: [Int: [PlannedLeg]] = [:]
    var failedSegmentsByDay: [Int: Int] = [:]
    var selectedDayIndex = 0
    var selectedPlaceID: TravelPlace.ID?
    var cameraPosition: MapCameraPosition
    var mapAppearance: MapAppearance = .standard
    var visibleLegCount = 0
    var isRouteLoading = false
    var activityTitle = ""
    var activityDetail = ""
    var noticeMessage: String?
    var errorMessage: String?
    var adjustmentText = ""
    var saveFeedbackTrigger = 0
    var libraryPresented = false

    let tripStore: TripStore

    @ObservationIgnored private let searchService: MapSearchService
    @ObservationIgnored private let routePlanner: RoutePlanner
    @ObservationIgnored private let intentParser: PlannerIntentParser
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryAction: RecoveryAction?
    @ObservationIgnored private var activeSavedTripID: SavedTrip.ID?
    @ObservationIgnored private var didBootstrap = false

    init(
        searchService: MapSearchService = MapSearchService(),
        routePlanner: RoutePlanner = RoutePlanner(),
        intentParser: PlannerIntentParser = PlannerIntentParser(),
        tripStore: TripStore = TripStore()
    ) {
        self.searchService = searchService
        self.routePlanner = routePlanner
        self.intentParser = intentParser
        self.tripStore = tripStore
        cameraPosition = .region(Self.initialRegion)
    }

    deinit {
        routeTask?.cancel()
        revealTask?.cancel()
    }

    var currentDay: ItineraryDay? {
        itineraryDays.first { $0.index == selectedDayIndex }
    }

    var currentStops: [TravelPlace] {
        currentDay?.stops ?? []
    }

    var currentLegs: [PlannedLeg] {
        routesByDay[selectedDayIndex] ?? []
    }

    var visibleLegs: [PlannedLeg] {
        Array(currentLegs.prefix(visibleLegCount))
    }

    var selectedPlace: TravelPlace? {
        currentStops.first { $0.id == selectedPlaceID }
    }

    var progressStep: Int {
        switch phase {
        case .destination: 0
        case .preferences: 1
        case .discovering: 2
        case .ready, .failure: 3
        }
    }

    var topTitle: String {
        destination?.title ?? "AnyTravel"
    }

    var topSubtitle: String {
        switch phase {
        case .destination: "地图正在等你的第一句话"
        case .preferences: draft.summary
        case .discovering: activityTitle
        case .ready: "\(draft.dayCount)天 · 路线随选择更新"
        case .failure: "需要调整后重试"
        }
    }

    var routeStatusText: String? {
        if isRouteLoading { return "正在向 Apple Maps 请求当天路线" }
        if phase == .discovering { return activityDetail }
        if !currentLegs.isEmpty, visibleLegCount < currentLegs.count {
            return "路线正在地图上展开"
        }
        if phase == .ready, !currentStops.isEmpty {
            return "第 \(selectedDayIndex + 1) 天路线已显示"
        }
        return nil
    }

    var routeSummary: String? {
        guard !currentLegs.isEmpty else { return nil }
        let seconds = currentLegs.reduce(0) { $0 + $1.route.expectedTravelTime }
        let meters = currentLegs.reduce(0) { $0 + $1.route.distance }
        let minutes = max(Int((seconds / 60).rounded()), 1)
        let distance: String
        if meters >= 1_000 {
            distance = String(format: "%.1f公里", meters / 1_000)
        } else {
            distance = "\(Int(meters.rounded()))米"
        }
        return "约\(minutes)分钟 · \(distance) · \(draft.travelMode.title)"
    }

    var canContinueDestination: Bool {
        !draft.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-ready") {
            seedUITestTrip()
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--demo-ready") {
            draft.destination = "苏州"
            await resolveDestination()
            if phase == .preferences {
                await generatePlan()
            }
        }
        #endif
    }

    #if DEBUG
    private func seedUITestTrip() {
        draft = TripDraft(destination: "苏州市", dayCount: 1)
        let center = Coordinate(latitude: 31.2989, longitude: 120.5853)
        destination = DestinationResolution(
            title: "苏州市",
            coordinate: center,
            region: MKCoordinateRegion(
                center: center.clLocationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )
        )
        itineraryDays = [
            ItineraryDay(
                index: 0,
                stops: [
                    TravelPlace(
                        name: "苏州博物馆",
                        address: "苏州市姑苏区东北街204号",
                        coordinate: Coordinate(latitude: 31.3247, longitude: 120.6230),
                        interest: .culture
                    ),
                    TravelPlace(
                        name: "拙政园",
                        address: "苏州市姑苏区东北街178号",
                        coordinate: Coordinate(latitude: 31.3265, longitude: 120.6251),
                        interest: .gardens
                    )
                ]
            )
        ]
        selectedDayIndex = 0
        phase = .ready
        fitCurrentDay(animated: false)
    }
    #endif

    func resolveDestination() async {
        routeTask?.cancel()
        revealTask?.cancel()
        noticeMessage = nil
        errorMessage = nil
        activityTitle = "正在定位 \(draft.destination)"
        activityDetail = "地图会在找到目的地后自动移动"
        phase = .discovering

        do {
            let resolution = try await searchService.resolveDestination(draft.destination)
            guard phase == .discovering else { return }
            destination = resolution
            draft.destination = resolution.title
            phase = .preferences
            recoveryAction = nil
            setCamera(.region(resolution.region), animated: true)
        } catch is CancellationError {
            return
        } catch {
            showFailure(error, recovery: .resolveDestination)
        }
    }

    func generatePlan() async {
        guard let destination else {
            await resolveDestination()
            guard self.destination != nil else { return }
            await generatePlan()
            return
        }

        routeTask?.cancel()
        revealTask?.cancel()
        routesByDay = [:]
        failedSegmentsByDay = [:]
        selectedPlaceID = nil
        selectedDayIndex = 0
        noticeMessage = nil
        errorMessage = nil
        activityTitle = "正在发现真实地点"
        activityDetail = "按目的地、偏好和距离筛选"
        phase = .discovering

        do {
            let places = try await searchService.discoverPlaces(around: destination, draft: draft)
            guard phase == .discovering else { return }
            activityTitle = "正在安排每天的顺序"
            activityDetail = "先把相近地点放进同一天"
            itineraryDays = routePlanner.orderPlaces(
                places,
                from: destination.coordinate,
                draft: draft
            )
            guard !itineraryDays.isEmpty else { throw PlanningError.placesNotFound }

            phase = .ready
            recoveryAction = nil
            fitCurrentDay(animated: true)
            await loadRoutesForSelectedDay(reveal: true)
        } catch is CancellationError {
            return
        } catch {
            showFailure(error, recovery: .generatePlan)
        }
    }

    func selectDay(_ dayIndex: Int) {
        guard itineraryDays.contains(where: { $0.index == dayIndex }) else { return }
        routeTask?.cancel()
        revealTask?.cancel()
        selectedDayIndex = dayIndex
        selectedPlaceID = nil
        visibleLegCount = 0
        noticeMessage = nil
        fitCurrentDay(animated: true)

        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
    }

    func selectPlace(_ place: TravelPlace) {
        revealTask?.cancel()
        visibleLegCount = currentLegs.count
        selectedPlaceID = place.id
        let camera = MapCamera(
            centerCoordinate: place.coordinate.clLocationCoordinate,
            distance: 1_200,
            heading: 0,
            pitch: mapAppearance == .standard ? 34 : 45
        )
        setCamera(.camera(camera), animated: true)
    }

    func dismissSelectedPlace() {
        selectedPlaceID = nil
        fitCurrentDay(animated: true)
    }

    func userMovedMap() {
        guard cameraPosition.positionedByUser else { return }
        revealTask?.cancel()
        visibleLegCount = currentLegs.count
    }

    func toggleInterest(_ interest: TripInterest) {
        if draft.interests.contains(interest) {
            guard draft.interests.count > 1 else {
                noticeMessage = "至少保留一个旅行偏好。"
                return
            }
            draft.interests.remove(interest)
        } else {
            draft.interests.insert(interest)
        }
    }

    func applyAdjustment() async {
        let intent = intentParser.parse(adjustmentText)
        guard intent.isRecognized else {
            noticeMessage = "这句话暂时还不会改路线，可以试试“轻松一点”或“多安排美食”。"
            return
        }

        if let pace = intent.pace { draft.pace = pace }
        if let travelMode = intent.travelMode { draft.travelMode = travelMode }
        if let dayCount = intent.dayCount { draft.dayCount = dayCount }
        if let budget = intent.budgetPerPerson { draft.budgetPerPerson = budget }
        draft.interests.formUnion(intent.addedInterests)
        draft.interests.subtract(intent.removedInterests)
        if draft.interests.isEmpty { draft.interests = [.gardens] }

        if let excludedTerm = intent.excludedPlaceTerm {
            let originalCount = itineraryDays.reduce(0) { $0 + $1.stops.count }
            itineraryDays = itineraryDays.compactMap { day in
                var updated = day
                updated.stops.removeAll {
                    $0.name.localizedCaseInsensitiveContains(excludedTerm)
                }
                return updated.stops.isEmpty ? nil : updated
            }
            let updatedCount = itineraryDays.reduce(0) { $0 + $1.stops.count }

            if updatedCount < originalCount {
                routesByDay = [:]
                failedSegmentsByDay = [:]
                selectedDayIndex = itineraryDays.first?.index ?? 0
                adjustmentText = ""
                noticeMessage = "已移除包含“\(excludedTerm)”的地点。"
                fitCurrentDay(animated: true)
                await loadRoutesForSelectedDay(reveal: true)
                return
            }

            noticeMessage = "当前路线里没有找到“\(excludedTerm)”。"
            return
        }

        adjustmentText = ""
        await generatePlan()
    }

    func saveCurrentTrip() {
        guard let destination, !itineraryDays.isEmpty else { return }

        let trip = SavedTrip(
            id: activeSavedTripID ?? UUID(),
            title: "\(destination.title) · \(draft.dayCount)天",
            draft: draft,
            destinationCenter: destination.coordinate,
            days: itineraryDays
        )

        do {
            try tripStore.save(trip)
            activeSavedTripID = trip.id
            noticeMessage = "行程已保存在这台设备上。"
            saveFeedbackTrigger += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSavedTrip(_ trip: SavedTrip) {
        routeTask?.cancel()
        revealTask?.cancel()
        activeSavedTripID = trip.id
        draft = trip.draft
        itineraryDays = trip.days
        routesByDay = [:]
        failedSegmentsByDay = [:]
        selectedDayIndex = trip.days.first?.index ?? 0
        selectedPlaceID = nil
        destination = DestinationResolution(
            title: trip.draft.destination,
            coordinate: trip.destinationCenter,
            region: MKCoordinateRegion(
                center: trip.destinationCenter.clLocationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.24)
            )
        )
        phase = .ready
        libraryPresented = false
        fitCurrentDay(animated: true)
        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
    }

    func deleteSavedTrip(_ trip: SavedTrip) {
        do {
            try tripStore.delete(trip)
            if activeSavedTripID == trip.id { activeSavedTripID = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry() async {
        switch recoveryAction {
        case .resolveDestination: await resolveDestination()
        case .generatePlan: await generatePlan()
        case nil: reset()
        }
    }

    func returnToEditing() {
        routeTask?.cancel()
        revealTask?.cancel()
        isRouteLoading = false
        errorMessage = nil
        noticeMessage = nil
        phase = destination == nil ? .destination : .preferences
    }

    func retryCurrentDayRoute() {
        routesByDay[selectedDayIndex] = nil
        failedSegmentsByDay[selectedDayIndex] = nil
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
    }

    func openInMaps(_ place: TravelPlace) {
        let coordinate = place.coordinate.clLocationCoordinate
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = place.name
        item.openInMaps()
    }

    func reset() {
        routeTask?.cancel()
        revealTask?.cancel()
        draft = TripDraft()
        phase = .destination
        destination = nil
        itineraryDays = []
        routesByDay = [:]
        failedSegmentsByDay = [:]
        selectedDayIndex = 0
        selectedPlaceID = nil
        visibleLegCount = 0
        isRouteLoading = false
        noticeMessage = nil
        errorMessage = nil
        adjustmentText = ""
        activeSavedTripID = nil
        cameraPosition = .region(Self.initialRegion)
    }

    func cycleMapAppearance() {
        let all = MapAppearance.allCases
        guard let index = all.firstIndex(of: mapAppearance) else { return }
        mapAppearance = all[(index + 1) % all.count]
    }

    private func loadRoutesForSelectedDay(reveal: Bool) async {
        guard let day = currentDay else { return }

        if let cached = routesByDay[day.index] {
            if reveal {
                revealRoutes(cached)
            } else {
                visibleLegCount = cached.count
            }
            return
        }

        isRouteLoading = true
        noticeMessage = nil
        defer { isRouteLoading = false }

        do {
            let result = try await routePlanner.buildRoutes(for: day, mode: draft.travelMode)
            guard phase == .ready, selectedDayIndex == day.index else { return }
            routesByDay[day.index] = result.legs
            failedSegmentsByDay[day.index] = result.failedSegments

            if result.failedSegments > 0 {
                noticeMessage = "有 \(result.failedSegments) 段路线暂未返回，已保留可用路段。"
            }

            if reveal {
                revealRoutes(result.legs)
            } else {
                visibleLegCount = result.legs.count
            }
        } catch is CancellationError {
            return
        } catch {
            routesByDay[day.index] = []
            failedSegmentsByDay[day.index] = max(day.stops.count - 1, 0)
            visibleLegCount = 0
            noticeMessage = "路线暂时无法加载；地点仍可查看，稍后切换日期可重试。"
            fitCurrentDay(animated: true)
        }
    }

    private func revealRoutes(_ legs: [PlannedLeg]) {
        revealTask?.cancel()

        guard !legs.isEmpty else {
            visibleLegCount = 0
            fitCurrentDay(animated: true)
            return
        }

        if UIAccessibility.isReduceMotionEnabled {
            visibleLegCount = legs.count
            fitCurrentDay(animated: false)
            return
        }

        visibleLegCount = 0
        revealTask = Task { [weak self] in
            guard let self else { return }
            for index in legs.indices {
                do {
                    try await Task.sleep(for: .milliseconds(index == 0 ? 180 : 520))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.42)) {
                    visibleLegCount = index + 1
                }
                setCamera(.rect(padded(legs[index].route.polyline.boundingMapRect)), animated: true)
            }

            do {
                try await Task.sleep(for: .milliseconds(620))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            fitCurrentDay(animated: true)
        }
    }

    private func fitCurrentDay(animated: Bool) {
        guard !currentStops.isEmpty else { return }

        if currentStops.count == 1, let coordinate = currentStops.first?.coordinate.clLocationCoordinate {
            setCamera(
                .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
                    )
                ),
                animated: animated
            )
            return
        }

        var rect = MKMapRect.null
        for stop in currentStops {
            let point = MKMapPoint(stop.coordinate.clLocationCoordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.union(pointRect)
        }
        setCamera(.rect(padded(rect)), animated: animated)
    }

    private func padded(_ rect: MKMapRect) -> MKMapRect {
        guard !rect.isNull else { return rect }
        let horizontal = max(rect.size.width * 0.40, 3_000)
        // The result panel floats over the lower part of the map. Extra vertical
        // breathing room keeps the first and last stops visible above that panel.
        let vertical = max(rect.size.height * 0.90, 5_000)
        let expanded = rect.insetBy(dx: -horizontal, dy: -vertical)
        return MKMapRect(
            x: expanded.origin.x,
            y: expanded.origin.y + rect.size.height * 0.30,
            width: expanded.size.width,
            height: expanded.size.height
        )
    }

    private func setCamera(_ position: MapCameraPosition, animated: Bool) {
        if animated, !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.smooth(duration: 0.72)) {
                cameraPosition = position
            }
        } else {
            cameraPosition = position
        }
    }

    private func showFailure(_ error: Error, recovery: RecoveryAction) {
        recoveryAction = recovery
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .failure
    }

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.35, longitude: 108.94),
        span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 31)
    )
}
