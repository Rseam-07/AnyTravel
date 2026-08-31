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
    var settingsPresented = false
    var planMapFocus: PlanMapFocus = .itinerary
    var accommodations: [AccommodationOption] = []
    var selectedAccommodationID: AccommodationOption.ID?
    var accessPoints: [AccessPoint] = []
    var transportOptions: [TransportOption] = []
    var selectedTransportID: TransportOption.ID?
    var isLogisticsLoading = false
    var logisticsStatusMessage: String?
    var originResolution: DestinationResolution?
    var activeProviderPage: ProviderBrowserDestination?

    let tripStore: TripStore

    @ObservationIgnored private let searchService: MapSearchService
    @ObservationIgnored private let routePlanner: RoutePlanner
    @ObservationIgnored private let intentParser: PlannerIntentParser
    @ObservationIgnored private let logisticsSearchService: LogisticsSearchService
    @ObservationIgnored private let transportEngine: TransportRecommendationEngine
    @ObservationIgnored private let expensePlanner: ExpensePlanner
    @ObservationIgnored private let scheduleBuilder: ScheduleBuilder
    @ObservationIgnored private let pricingBackendClient: PricingBackendClient
    @ObservationIgnored private let preferencesStore: PlannerPreferencesStore
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var logisticsTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryAction: RecoveryAction?
    @ObservationIgnored private var activeSavedTripID: SavedTrip.ID?
    @ObservationIgnored private var didBootstrap = false

    init(
        searchService: MapSearchService = MapSearchService(),
        routePlanner: RoutePlanner = RoutePlanner(),
        intentParser: PlannerIntentParser = PlannerIntentParser(),
        logisticsSearchService: LogisticsSearchService = LogisticsSearchService(),
        transportEngine: TransportRecommendationEngine = TransportRecommendationEngine(),
        expensePlanner: ExpensePlanner = ExpensePlanner(),
        scheduleBuilder: ScheduleBuilder = ScheduleBuilder(),
        pricingBackendClient: PricingBackendClient = PricingBackendClient(),
        preferencesStore: PlannerPreferencesStore = PlannerPreferencesStore(),
        tripStore: TripStore = TripStore()
    ) {
        self.searchService = searchService
        self.routePlanner = routePlanner
        self.intentParser = intentParser
        self.logisticsSearchService = logisticsSearchService
        self.transportEngine = transportEngine
        self.expensePlanner = expensePlanner
        self.scheduleBuilder = scheduleBuilder
        self.pricingBackendClient = pricingBackendClient
        self.preferencesStore = preferencesStore
        self.tripStore = tripStore
        draft = preferencesStore.applyingSavedPreferences()
        cameraPosition = .region(Self.initialRegion)
    }

    deinit {
        routeTask?.cancel()
        revealTask?.cancel()
        logisticsTask?.cancel()
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

    var selectedAccommodation: AccommodationOption? {
        accommodations.first { $0.id == selectedAccommodationID }
    }

    var selectedTransport: TransportOption? {
        transportOptions.first { $0.id == selectedTransportID }
    }

    var expenseLines: [ExpenseLine] {
        expensePlanner.buildLines(
            draft: draft,
            accommodation: selectedAccommodation,
            transport: selectedTransport
        )
    }

    var plannedExpenseTotal: Int {
        expenseLines.reduce(0) { $0 + $1.amountCNY }
    }

    var totalBudget: Int {
        draft.budgetPerPerson * max(draft.logistics.travelers, 1)
    }

    var currentSchedule: [ScheduleItem] {
        guard let currentDay else { return [] }
        return scheduleBuilder.build(
            for: currentDay,
            pace: draft.pace,
            accommodation: selectedAccommodation
        )
    }

    var visibleAccommodations: [AccommodationOption] {
        planMapFocus == .accommodation ? Array(accommodations.prefix(8)) : []
    }

    var visibleAccessPoints: [AccessPoint] {
        guard planMapFocus == .transport else { return [] }
        if let point = selectedTransport?.arrivalAccessPoint { return [point] }
        return Array(accessPoints.filter { $0.kind != .metro }.prefix(6))
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
        case .destination: "地图正等你说出下一处远方"
        case .preferences: draft.summary
        case .discovering: activityTitle
        case .ready: "\(draft.dayCount)天 · 每次选择都落在地图上"
        case .failure: "这一段路需要重新接上"
        }
    }

    var routeStatusText: String? {
        if isLogisticsLoading { return logisticsStatusMessage ?? "正在寻找住处与抵达方式" }
        if isRouteLoading { return "正在请 Apple Maps 铺开当天路线" }
        if phase == .discovering { return activityDetail }
        if !currentLegs.isEmpty, visibleLegCount < currentLegs.count {
            return "路线正沿着地图缓缓展开"
        }
        if phase == .ready, !currentStops.isEmpty {
            return "第 \(selectedDayIndex + 1) 天的脚步已经落在地图上"
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
        var logistics = TripLogistics()
        logistics.origin = "上海"
        logistics.startDate = Calendar.current.date(byAdding: .day, value: 7, to: .now)
        logistics.endDate = Calendar.current.date(byAdding: .day, value: 9, to: .now)
        logistics.travelers = 2
        logistics.preferredLongDistanceMode = .train
        draft = TripDraft(destination: "苏州市", dayCount: 3, logistics: logistics)
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
        let hotel = AccommodationOption(
            name: "苏州园林附近酒店",
            address: "苏州市姑苏区",
            coordinate: Coordinate(latitude: 31.3218, longitude: 120.6188),
            attractionDistanceMeters: 780,
            accessDistances: [.metro: 420, .rail: 4_600],
            quotes: [
                ProviderQuote(provider: .ctrip, amountCNY: 468, unit: .perNight, kind: .demo, capturedAt: .now, bookingURL: URL(string: "https://hotels.ctrip.com/"), note: "仅用于界面验收，不作为实时价格"),
                ProviderQuote(provider: .qunar, amountCNY: 489, unit: .perNight, kind: .demo, capturedAt: .now, bookingURL: URL(string: "https://hotel.qunar.com/"), note: "仅用于界面验收，不作为实时价格")
            ],
            recommendationReasons: ["到行程景点平均780米", "距地铁约420米"]
        )
        accommodations = [hotel]
        selectedAccommodationID = hotel.id
        let station = AccessPoint(name: "苏州站", coordinate: Coordinate(latitude: 31.3302, longitude: 120.6060), kind: .rail)
        accessPoints = [station]
        let train = TransportOption(
            mode: .train,
            title: "高铁抵达苏州",
            originName: "上海",
            destinationName: "苏州",
            durationMinutes: 75,
            arrivalAccessPoint: station,
            hotelTransferMeters: 4_600,
            quotes: [ProviderQuote(provider: .railway12306, amountCNY: 39, unit: .perPerson, kind: .demo, capturedAt: .now, bookingURL: URL(string: "https://kyfw.12306.cn/otn/leftTicket/init"), note: "仅用于界面验收")],
            recommendationReasons: ["你已优先选择这种方式", "苏州站到住宿约4.6公里"],
            isRecommended: true
        )
        transportOptions = [train]
        selectedTransportID = train.id
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
        activityTitle = "正在寻找 \(draft.destination)"
        activityDetail = "找到以后，地图会带你向那边移动"
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
        activityTitle = "正在拾起沿途值得停留的地方"
        activityDetail = "依照目的地、偏好与距离慢慢筛选"
        phase = .discovering

        do {
            let places = try await searchService.discoverPlaces(around: destination, draft: draft)
            guard phase == .discovering else { return }
            activityTitle = "正在编排每天的脚步"
            activityDetail = "先让相近的地方在同一天相遇"
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
            refreshLogisticsInBackground()
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
            days: itineraryDays,
            logisticsSnapshot: LogisticsSnapshot(
                accommodations: accommodations,
                selectedAccommodationID: selectedAccommodationID,
                transportOptions: transportOptions,
                selectedTransportID: selectedTransportID
            )
        )

        do {
            try tripStore.save(trip)
            activeSavedTripID = trip.id
            noticeMessage = "这段旅程已收进本机旅册。"
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
        if let snapshot = trip.logisticsSnapshot {
            accommodations = snapshot.accommodations
            selectedAccommodationID = snapshot.selectedAccommodationID
            transportOptions = snapshot.transportOptions
            selectedTransportID = snapshot.selectedTransportID
        } else {
            accommodations = []
            selectedAccommodationID = nil
            transportOptions = []
            selectedTransportID = nil
        }
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
        if trip.logisticsSnapshot == nil {
            refreshLogisticsInBackground()
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
        logisticsTask?.cancel()
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

    func setDatesEnabled(_ enabled: Bool) {
        if enabled {
            let start = Calendar.current.startOfDay(
                for: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
            )
            draft.logistics.startDate = start
            draft.logistics.endDate = Calendar.current.date(
                byAdding: .day,
                value: max(draft.dayCount - 1, 1),
                to: start
            )
        } else {
            draft.logistics.startDate = nil
            draft.logistics.endDate = nil
        }
    }

    func updateStartDate(_ date: Date) {
        let start = Calendar.current.startOfDay(for: date)
        draft.logistics.startDate = start
        if let end = draft.logistics.endDate, end > start { return }
        draft.logistics.endDate = Calendar.current.date(
            byAdding: .day,
            value: max(draft.dayCount - 1, 1),
            to: start
        )
    }

    func updateEndDate(_ date: Date) {
        guard let start = draft.logistics.startDate else {
            draft.logistics.endDate = date
            return
        }
        let minimumEnd = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let end = max(date, minimumEnd)
        draft.logistics.endDate = end
        let nights = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
        draft.dayCount = min(max(nights + 1, 1), 7)
    }

    func refreshLogisticsInBackground() {
        logisticsTask?.cancel()
        logisticsTask = Task { [weak self] in
            await self?.refreshLogistics()
        }
    }

    func refreshLogistics() async {
        guard let destination else { return }
        isLogisticsLoading = true
        logisticsStatusMessage = "正在寻找落脚处与抵达的车站"
        defer { isLogisticsLoading = false }

        if draft.logistics.skipAccommodation {
            accommodations = []
            selectedAccommodationID = nil
            accessPoints = await logisticsSearchService.discoverAccessPoints(
                around: destination,
                destinationName: draft.destination
            )
        } else {
            let previousName = selectedAccommodation?.name
            let discovery = await logisticsSearchService.discoverAccommodations(
                around: destination,
                itineraryDays: itineraryDays,
                draft: draft
            )
            guard !Task.isCancelled else { return }
            logisticsStatusMessage = draft.logistics.hasDates ? "正在把当天的住宿价格带回来" : "正在沿景点整理合适的落脚处"
            accommodations = await pricingBackendClient.enrichAccommodationQuotes(
                discovery.options,
                destination: draft.destination,
                logistics: draft.logistics
            )
            accessPoints = discovery.accessPoints
            selectedAccommodationID = accommodations.first(where: { $0.name == previousName })?.id
                ?? accommodations.first?.id
        }

        logisticsStatusMessage = "正在把抵达方式与落脚处接在一起"
        originResolution = nil
        let trimmedOrigin = draft.logistics.origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOrigin.isEmpty {
            originResolution = try? await searchService.resolveDestination(trimmedOrigin)
        }
        guard !Task.isCancelled else { return }
        rebuildTransportOptions()
        if draft.logistics.hasDates, !trimmedOrigin.isEmpty {
            logisticsStatusMessage = "正在读取班次、余票与这一刻的价格"
            await refreshTransportQuotes()
        }

        if accommodations.isEmpty, !draft.logistics.skipAccommodation {
            logisticsStatusMessage = "附近住宿暂未返回，可稍后刷新"
        } else if originResolution == nil, !trimmedOrigin.isEmpty {
            logisticsStatusMessage = "出发地未定位，交通先按待定展示"
        } else {
            logisticsStatusMessage = nil
        }
    }

    func selectAccommodation(_ option: AccommodationOption) {
        selectedAccommodationID = option.id
        selectedPlaceID = nil
        rebuildTransportOptions()
        if draft.logistics.hasDates,
           !draft.logistics.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logisticsTask?.cancel()
            logisticsTask = Task { [weak self] in
                guard let self else { return }
                self.isLogisticsLoading = true
                self.logisticsStatusMessage = "正在从新住处重新丈量抵达的路"
                await self.refreshTransportQuotes()
                self.isLogisticsLoading = false
                self.logisticsStatusMessage = nil
            }
        }
        let camera = MapCamera(
            centerCoordinate: option.coordinate.clLocationCoordinate,
            distance: 1_500,
            heading: 0,
            pitch: mapAppearance == .standard ? 32 : 44
        )
        setCamera(.camera(camera), animated: true)
    }

    func selectTransport(_ option: TransportOption) {
        selectedTransportID = option.id
        if let accessPoint = option.arrivalAccessPoint {
            fitCoordinates(
                [accessPoint.coordinate, selectedAccommodation?.coordinate].compactMap { $0 },
                animated: true
            )
        }
    }

    func setPlanMapFocus(_ focus: PlanMapFocus) {
        planMapFocus = focus
        selectedPlaceID = nil
        switch focus {
        case .itinerary, .budget:
            fitCurrentDay(animated: true)
        case .accommodation:
            let coordinates = accommodations.prefix(8).map(\.coordinate) + currentStops.map(\.coordinate)
            fitCoordinates(coordinates, animated: true)
        case .transport:
            let coordinates = [selectedTransport?.arrivalAccessPoint?.coordinate, selectedAccommodation?.coordinate]
                .compactMap { $0 }
            if coordinates.isEmpty {
                fitCurrentDay(animated: true)
            } else {
                fitCoordinates(coordinates, animated: true)
            }
        }
    }

    func openQuote(_ quote: ProviderQuote) {
        guard let url = quote.bookingURL else {
            noticeMessage = "\(quote.provider.title) 的购买链接会在报价适配器返回后出现。"
            return
        }
        if let provider = ProviderAccount(travelProvider: quote.provider) {
            activeProviderPage = ProviderBrowserDestination(
                provider: provider,
                url: url,
                title: quote.provider.title
            )
        } else {
            UIApplication.shared.open(url)
        }
    }

    func persistPlanningDefaults() {
        preferencesStore.save(from: draft)
    }

    private func rebuildTransportOptions() {
        guard let destination else { return }
        let previousMode = selectedTransport?.mode ?? draft.logistics.preferredLongDistanceMode
        transportOptions = transportEngine.buildOptions(
            origin: originResolution,
            destination: destination,
            accessPoints: accessPoints,
            selectedAccommodation: selectedAccommodation,
            draft: draft
        )
        selectedTransportID = transportOptions.first(where: { $0.mode == previousMode })?.id
            ?? transportOptions.first(where: \.isRecommended)?.id
            ?? transportOptions.first?.id
    }

    private func refreshTransportQuotes() async {
        let updated = await pricingBackendClient.enrichTransportOptions(
            transportOptions,
            origin: draft.logistics.origin,
            destination: draft.destination,
            logistics: draft.logistics,
            accessPoints: accessPoints,
            accommodation: selectedAccommodation
        )
        guard !Task.isCancelled else { return }
        transportOptions = updated
        if !transportOptions.contains(where: { $0.id == selectedTransportID }) {
            selectedTransportID = transportOptions.first(where: \.isRecommended)?.id
                ?? transportOptions.first?.id
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
        logisticsTask?.cancel()
        draft = preferencesStore.applyingSavedPreferences()
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
        planMapFocus = .itinerary
        accommodations = []
        selectedAccommodationID = nil
        accessPoints = []
        transportOptions = []
        selectedTransportID = nil
        isLogisticsLoading = false
        logisticsStatusMessage = nil
        originResolution = nil
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

    private func fitCoordinates(_ coordinates: [Coordinate], animated: Bool) {
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1, let coordinate = coordinates.first {
            setCamera(
                .region(
                    MKCoordinateRegion(
                        center: coordinate.clLocationCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                ),
                animated: animated
            )
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate.clLocationCoordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
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
