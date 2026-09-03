import CoreLocation
import MapKit
import Observation
import SwiftUI
import UIKit

@Observable
final class PlannerViewModel {
    private struct ItineraryEditSnapshot: Equatable {
        var days: [ItineraryDay]
        var selectedDayIndex: Int
        var selectedPlaceID: TravelPlace.ID?
    }

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
    var travelRequestText = ""
    var adjustmentText = ""
    var saveFeedbackTrigger = 0
    var planReadyFeedbackTrigger = 0
    var mapActionFeedbackTrigger = 0
    var libraryPresented = false
    var settingsPresented = false
    var itineraryEditorPresented = false
    var conditionsEditorPresented = false
    var canUndoItineraryChange = false
    var canRedoItineraryChange = false
    var planMapFocus: PlanMapFocus = .itinerary
    var accommodations: [AccommodationOption] = []
    var selectedAccommodationID: AccommodationOption.ID?
    var accommodationSort: AccommodationSort = .recommended
    var accommodationMaxNightlyPrice: Int?
    var accommodationMaxAttractionDistanceMeters: Double?
    var accommodationLivePricesOnly = false
    var accommodationOfficialSiteOnly = false
    var accessPoints: [AccessPoint] = []
    var transportOptions: [TransportOption] = []
    var selectedTransportID: TransportOption.ID?
    var returnTransportOptions: [TransportOption] = []
    var selectedReturnTransportID: TransportOption.ID?
    var outboundTransferOptions: [LocalTransferOption] = []
    var selectedOutboundTransferID: LocalTransferOption.ID?
    var returnTransferOptions: [LocalTransferOption] = []
    var selectedReturnTransferID: LocalTransferOption.ID?
    var focusedTransportDirection: TransportDirection = .outbound
    var transferRoutesByOptionID: [LocalTransferOption.ID: MKRoute] = [:]
    var isTransferLoading = false
    var transferStatusMessage: String?
    var isExportingPlan = false
    var exportStatusMessage: String?
    var sharePayload: PlanSharePayload?
    var exportFeedbackTrigger = 0
    var paceFeedbackTrigger = 0
    var paceStatusMessage: String?
    var isAssistantResponding = false
    var assistantReply: String?
    var assistantFeedbackTrigger = 0
    var isLogisticsLoading = false
    var logisticsStatusMessage: String?
    var quoteRefreshState: QuoteRefreshState = .idle
    var originResolution: DestinationResolution?
    var activeProviderPage: ProviderBrowserDestination?
    var attractionPickerPresented = false
    var attractionCandidates: [TravelPlace] = []
    var selectedAttractionIDs: Set<TravelPlace.ID> = []
    var isAttractionDiscoveryLoading = false
    var attractionSelectionMessage: String?

    let tripStore: TripStore
    let assistantSettings: AssistantSettingsStore

    @ObservationIgnored private let searchService: MapSearchService
    @ObservationIgnored private let routePlanner: RoutePlanner
    @ObservationIgnored private let intentParser: PlannerIntentParser
    @ObservationIgnored private let logisticsSearchService: LogisticsSearchService
    @ObservationIgnored private let transportEngine: TransportRecommendationEngine
    @ObservationIgnored private let localTransferService: LocalTransferService
    @ObservationIgnored private let planExportService: PlanExportService
    @ObservationIgnored private let planPacingService: PlanPacingService
    @ObservationIgnored private let tourismDayAssessmentService = TourismDayAssessmentService()
    @ObservationIgnored private let assistantClient: TravelAssistantClient
    @ObservationIgnored private let expensePlanner: ExpensePlanner
    @ObservationIgnored private let scheduleBuilder: ScheduleBuilder
    @ObservationIgnored private let pricingBackendClient: PricingBackendClient
    @ObservationIgnored private let rollingGoDirectClient: RollingGoDirectClient
    @ObservationIgnored private let railway12306DirectClient: Railway12306DirectClient
    @ObservationIgnored private let fliggyFlightDirectClient: FliggyFlightDirectClient
    @ObservationIgnored private let qunarFlightDirectClient: QunarFlightDirectClient
    @ObservationIgnored private let preferencesStore: PlannerPreferencesStore
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var logisticsTask: Task<Void, Never>?
    @ObservationIgnored private var transferTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryAction: RecoveryAction?
    @ObservationIgnored private var activeSavedTripID: SavedTrip.ID?
    @ObservationIgnored private var itineraryNeedsLogisticsRefresh = false
    @ObservationIgnored private var itineraryUndoStack: [ItineraryEditSnapshot] = []
    @ObservationIgnored private var itineraryRedoStack: [ItineraryEditSnapshot] = []
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var plannedAttractionPlaces: [TravelPlace] = []
    @ObservationIgnored private var pendingPlanNoticeMessage: String?

    init(
        searchService: MapSearchService = MapSearchService(),
        routePlanner: RoutePlanner = RoutePlanner(),
        intentParser: PlannerIntentParser = PlannerIntentParser(),
        logisticsSearchService: LogisticsSearchService = LogisticsSearchService(),
        transportEngine: TransportRecommendationEngine = TransportRecommendationEngine(),
        localTransferService: LocalTransferService = LocalTransferService(),
        planExportService: PlanExportService = PlanExportService(),
        planPacingService: PlanPacingService = PlanPacingService(),
        assistantClient: TravelAssistantClient = TravelAssistantClient(),
        assistantSettings: AssistantSettingsStore = AssistantSettingsStore(),
        expensePlanner: ExpensePlanner = ExpensePlanner(),
        scheduleBuilder: ScheduleBuilder = ScheduleBuilder(),
        pricingBackendClient: PricingBackendClient = PricingBackendClient(),
        rollingGoDirectClient: RollingGoDirectClient = RollingGoDirectClient(),
        railway12306DirectClient: Railway12306DirectClient = Railway12306DirectClient(),
        fliggyFlightDirectClient: FliggyFlightDirectClient = FliggyFlightDirectClient(),
        qunarFlightDirectClient: QunarFlightDirectClient = QunarFlightDirectClient(),
        preferencesStore: PlannerPreferencesStore = PlannerPreferencesStore(),
        tripStore: TripStore = TripStore()
    ) {
        self.searchService = searchService
        self.routePlanner = routePlanner
        self.intentParser = intentParser
        self.logisticsSearchService = logisticsSearchService
        self.transportEngine = transportEngine
        self.localTransferService = localTransferService
        self.planExportService = planExportService
        self.planPacingService = planPacingService
        self.assistantClient = assistantClient
        self.assistantSettings = assistantSettings
        self.expensePlanner = expensePlanner
        self.scheduleBuilder = scheduleBuilder
        self.pricingBackendClient = pricingBackendClient
        self.rollingGoDirectClient = rollingGoDirectClient
        self.railway12306DirectClient = railway12306DirectClient
        self.fliggyFlightDirectClient = fliggyFlightDirectClient
        self.qunarFlightDirectClient = qunarFlightDirectClient
        self.preferencesStore = preferencesStore
        self.tripStore = tripStore
        draft = preferencesStore.applyingSavedPreferences()
        cameraPosition = .region(Self.initialRegion)
    }

    deinit {
        routeTask?.cancel()
        revealTask?.cancel()
        logisticsTask?.cancel()
        transferTask?.cancel()
        exportTask?.cancel()
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

    var selectedReturnTransport: TransportOption? {
        returnTransportOptions.first { $0.id == selectedReturnTransportID }
    }

    var selectedOutboundTransfer: LocalTransferOption? {
        outboundTransferOptions.first { $0.id == selectedOutboundTransferID }
    }

    var selectedReturnTransfer: LocalTransferOption? {
        returnTransferOptions.first { $0.id == selectedReturnTransferID }
    }

    var visibleTransferRoute: MKRoute? {
        guard planMapFocus == .transport else { return nil }
        let selectedID = focusedTransportDirection == .outbound
            ? selectedOutboundTransferID
            : selectedReturnTransferID
        return selectedID.flatMap { transferRoutesByOptionID[$0] }
    }

    var expenseLines: [ExpenseLine] {
        expensePlanner.buildLines(
            draft: draft,
            accommodation: selectedAccommodation,
            transport: selectedTransport,
            returnTransport: selectedReturnTransport,
            outboundTransfer: selectedOutboundTransfer,
            returnTransfer: selectedReturnTransfer,
            itineraryDays: itineraryDays
        )
    }

    var plannedExpenseTotal: Int {
        expenseLines.reduce(0) { $0 + $1.amountCNY }
    }

    var totalBudget: Int {
        draft.budgetPerPerson * max(draft.logistics.travelers, 1)
    }

    var canExportCalendar: Bool {
        draft.logistics.startDate != nil && !itineraryDays.isEmpty
    }

    var planPacingAssessment: PlanPacingAssessment {
        planPacingService.assess(
            days: itineraryDays,
            travelMinutesByDay: routeTravelMinutesByDay,
            failedSegmentsByDay: failedSegmentsByDay,
            pace: draft.pace,
            mode: draft.travelMode,
            constraintsByDay: tourismConstraintsByDay
        )
    }

    var currentSchedule: [ScheduleItem] {
        guard let currentDay else { return [] }
        return scheduleBuilder.build(
            for: currentDay,
            pace: draft.pace,
            accommodation: selectedAccommodation,
            travelMode: draft.travelMode,
            constraints: tourismConstraints(for: currentDay)
        )
    }

    var currentDayTourismAssessment: TourismDayAssessment? {
        guard let currentDay else { return nil }
        return tourismDayAssessmentService.assess(
            day: currentDay,
            pace: draft.pace,
            mode: draft.travelMode,
            actualTravelMinutes: routeTravelMinutesByDay[currentDay.index],
            constraints: tourismConstraints(for: currentDay)
        )
    }

    var visibleAccommodations: [AccommodationOption] {
        planMapFocus == .accommodation ? Array(filteredAccommodations.prefix(16)) : []
    }

    var filteredAccommodations: [AccommodationOption] {
        accommodations
            .filter { option in
                if let maximum = accommodationMaxNightlyPrice {
                    guard let amount = option.bestPricedQuote?.amountCNY, amount <= maximum else { return false }
                }
                if let maximumDistance = accommodationMaxAttractionDistanceMeters,
                   option.attractionDistanceMeters > maximumDistance {
                    return false
                }
                if accommodationLivePricesOnly,
                   !option.quotes.contains(where: { $0.amountCNY != nil && ($0.kind == .live || $0.kind == .indicative) }) {
                    return false
                }
                if accommodationOfficialSiteOnly, option.officialWebsiteURL == nil { return false }
                return true
            }
            .sorted(by: accommodationComparator)
    }

    var activeAccommodationFilterCount: Int {
        [
            accommodationMaxNightlyPrice != nil,
            accommodationMaxAttractionDistanceMeters != nil,
            accommodationLivePricesOnly,
            accommodationOfficialSiteOnly
        ].filter(\.self).count
    }

    private func accommodationComparator(_ lhs: AccommodationOption, _ rhs: AccommodationOption) -> Bool {
        switch accommodationSort {
        case .recommended:
            let lhsPrice = Double(lhs.bestPricedQuote?.amountCNY ?? 2_500)
            let rhsPrice = Double(rhs.bestPricedQuote?.amountCNY ?? 2_500)
            let lhsTransit = lhs.accessDistances[.metro] ?? lhs.accessDistances[.rail] ?? 8_000
            let rhsTransit = rhs.accessDistances[.metro] ?? rhs.accessDistances[.rail] ?? 8_000
            return lhs.attractionDistanceMeters + lhsTransit * 0.22 + lhsPrice * 0.55
                < rhs.attractionDistanceMeters + rhsTransit * 0.22 + rhsPrice * 0.55
        case .lowestPrice:
            return (lhs.bestPricedQuote?.amountCNY ?? .max) < (rhs.bestPricedQuote?.amountCNY ?? .max)
        case .closestToAttractions:
            return lhs.attractionDistanceMeters < rhs.attractionDistanceMeters
        case .closestToTransit:
            let lhsDistance = lhs.accessDistances[.metro] ?? lhs.accessDistances[.rail] ?? .greatestFiniteMagnitude
            let rhsDistance = rhs.accessDistances[.metro] ?? rhs.accessDistances[.rail] ?? .greatestFiniteMagnitude
            return lhsDistance < rhsDistance
        }
    }

    var visibleAccessPoints: [AccessPoint] {
        guard planMapFocus == .transport else { return [] }
        let selectedPoints = [
            selectedTransport?.arrivalAccessPoint,
            selectedReturnTransport?.arrivalAccessPoint
        ].compactMap { $0 }
        if !selectedPoints.isEmpty {
            return selectedPoints.reduce(into: []) { points, point in
                guard !points.contains(where: { $0.name == point.name && $0.kind == point.kind }) else { return }
                points.append(point)
            }
        }
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

    var canSubmitTravelRequest: Bool {
        !travelRequestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var suggestedAttractionCount: Int {
        min(max(draft.dayCount, 1) * draft.pace.stopsPerDay, 20)
    }

    var attractionSelectionPressureMessage: String? {
        let selectedCount = selectedAttractionIDs.count
        guard selectedCount > suggestedAttractionCount else { return nil }
        return "已选 \(selectedCount) 处，超过当前\(draft.pace.title)节奏约 \(suggestedAttractionCount) 处的舒适容量；会全部保留，但部分日期可能偏赶。"
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-preferences") {
            seedUITestPreferences()
            return
        }

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
    private func seedUITestPreferences() {
        var logistics = TripLogistics()
        logistics.origin = "宁波"
        logistics.startDate = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 8, to: .now) ?? .now
        )
        logistics.endDate = Calendar.current.date(byAdding: .day, value: 2, to: logistics.startDate ?? .now)
        logistics.travelers = 2
        draft = TripDraft(destination: "天津市", dayCount: 3, logistics: logistics)
        let center = Coordinate(latitude: 39.0842, longitude: 117.2009)
        destination = DestinationResolution(
            title: "天津市",
            coordinate: center,
            region: MKCoordinateRegion(
                center: center.clLocationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
            )
        )
        cameraPosition = .region(destination?.region ?? Self.initialRegion)
        phase = .preferences
    }

    private func seedUITestTrip() {
        var logistics = TripLogistics()
        logistics.origin = "上海"
        logistics.startDate = Calendar.current.date(byAdding: .day, value: 7, to: .now)
        logistics.endDate = Calendar.current.date(byAdding: .day, value: 9, to: .now)
        logistics.travelers = 2
        logistics.preferredLongDistanceMode = .train
        draft = TripDraft(destination: "苏州市", dayCount: 3, logistics: logistics)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-busy") {
            draft.pace = .full
        }
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
                    ),
                    TravelPlace(
                        name: "狮子林",
                        address: "苏州市姑苏区园林路23号",
                        coordinate: Coordinate(latitude: 31.3231, longitude: 120.6290),
                        interest: .gardens
                    ),
                    TravelPlace(
                        name: "山塘街",
                        address: "苏州市姑苏区山塘街",
                        coordinate: Coordinate(latitude: 31.3173, longitude: 120.5964),
                        interest: .culture
                    ),
                    TravelPlace(
                        name: "网师园",
                        address: "苏州市姑苏区阔家头巷11号",
                        coordinate: Coordinate(latitude: 31.3012, longitude: 120.6301),
                        interest: .gardens
                    )
                ]
            ),
            ItineraryDay(
                index: 1,
                stops: [
                    TravelPlace(
                        name: "平江路",
                        address: "苏州市姑苏区平江路",
                        coordinate: Coordinate(latitude: 31.3114, longitude: 120.6297),
                        interest: .culture
                    )
                ]
            ),
            ItineraryDay(
                index: 2,
                stops: [
                    TravelPlace(
                        name: "虎丘",
                        address: "苏州市姑苏区虎丘山门内8号",
                        coordinate: Coordinate(latitude: 31.3389, longitude: 120.5775),
                        interest: .gardens
                    )
                ]
            )
        ]
        if !ProcessInfo.processInfo.arguments.contains("--ui-test-busy") {
            itineraryDays[0].stops.removeLast(3)
        }
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
        let returnTrain = TransportOption(
            mode: .train,
            title: "G7028 · 苏州→上海",
            originName: "苏州",
            destinationName: "上海",
            direction: .returnTrip,
            durationMinutes: 32,
            arrivalAccessPoint: station,
            hotelTransferMeters: 4_600,
            quotes: [ProviderQuote(provider: .railway12306, amountCNY: 40, unit: .perPerson, kind: .demo, capturedAt: .now, bookingURL: URL(string: "https://kyfw.12306.cn/otn/leftTicket/init"), note: "返程演示价，仅用于界面验收")],
            recommendationReasons: ["17:02–17:34 · 二等座有票", "住宿到苏州站约4.6公里"],
            isRecommended: true
        )
        transportOptions = [train]
        selectedTransportID = train.id
        returnTransportOptions = [returnTrain]
        selectedReturnTransportID = returnTrain.id
        let arrivalMetro = LocalTransferOption(
            direction: .outbound,
            mode: .publicTransit,
            originName: "苏州站",
            destinationName: hotel.name,
            durationMinutes: 26,
            distanceMeters: 5_200,
            estimatedCostCNY: 8,
            routeKind: .preview,
            costNote: "按 2 人与里程估算，实际票制以当地为准",
            recommendationReasons: ["时间、费用与换乘负担更均衡", "Apple Maps 路线约 5.2公里"],
            isRecommended: true
        )
        let arrivalTaxi = LocalTransferOption(
            direction: .outbound,
            mode: .taxi,
            originName: "苏州站",
            destinationName: hotel.name,
            durationMinutes: 18,
            distanceMeters: 6_100,
            estimatedCostCNY: 28,
            routeKind: .preview,
            costNote: "按里程与行车时间估算，不是网约车实时报价",
            recommendationReasons: ["少一次换乘", "Apple Maps 驾车路线约 6.1公里"]
        )
        let returnMetro = LocalTransferOption(
            direction: .returnTrip,
            mode: .publicTransit,
            originName: hotel.name,
            destinationName: "苏州站",
            durationMinutes: 28,
            distanceMeters: 5_300,
            estimatedCostCNY: 8,
            routeKind: .preview,
            costNote: "按 2 人与里程估算，实际票制以当地为准",
            recommendationReasons: ["时间、费用与换乘负担更均衡", "建议至少提前 50 分钟出发"],
            isRecommended: true
        )
        outboundTransferOptions = [arrivalMetro, arrivalTaxi]
        selectedOutboundTransferID = arrivalMetro.id
        returnTransferOptions = [returnMetro]
        selectedReturnTransferID = returnMetro.id
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
            plannedAttractionPlaces = []
            attractionCandidates = []
            selectedAttractionIDs = []
            phase = .preferences
            recoveryAction = nil
            setCamera(.region(resolution.region), animated: true)
        } catch is CancellationError {
            return
        } catch {
            showFailure(error, recovery: .resolveDestination)
        }
    }

    func requestPlan() async {
        if phase == .preferences {
            await beginAttractionSelection()
        } else {
            await generatePlan()
        }
    }

    func beginAttractionSelection() async {
        guard let destination else {
            await resolveDestination()
            guard self.destination != nil else { return }
            await beginAttractionSelection()
            return
        }
        attractionPickerPresented = true
        isAttractionDiscoveryLoading = true
        attractionSelectionMessage = nil
        do {
            let candidates = try await searchService.discoverAttractionCandidates(
                around: destination,
                draft: draft
            )
            guard attractionPickerPresented else { return }
            attractionCandidates = candidates
            selectedAttractionIDs = selectedAttractionIDs.intersection(Set(candidates.map(\.id)))
        } catch {
            attractionSelectionMessage = error.localizedDescription
        }
        isAttractionDiscoveryLoading = false
    }

    func toggleAttractionSelection(_ place: TravelPlace) {
        if selectedAttractionIDs.contains(place.id) {
            selectedAttractionIDs.remove(place.id)
        } else {
            selectedAttractionIDs.insert(place.id)
        }
    }

    func confirmAttractionSelection(automatic: Bool) async {
        guard !attractionCandidates.isEmpty else {
            attractionSelectionMessage = "还没有找到能落在地图上的景点，请稍后重试。"
            return
        }
        let explicitIDs = automatic ? Set<TravelPlace.ID>() : selectedAttractionIDs
        var selected = attractionCandidates.filter { explicitIDs.contains($0.id) }
        selected = selected.map {
            var place = $0
            place.planningPriority = .primary
            return place
        }
        let targetCount = suggestedAttractionCount
        let supplemental = attractionCandidates.filter { !explicitIDs.contains($0.id) }
        for original in supplemental where selected.count < targetCount {
            var place = original
            place.planningPriority = .supplemental
            selected.append(place)
        }
        plannedAttractionPlaces = selected
        attractionPickerPresented = false
        if automatic {
            pendingPlanNoticeMessage = "已按在线热度、偏好与空间分布替你挑选 \(selected.count) 处停留。"
        } else if explicitIDs.count < targetCount {
            pendingPlanNoticeMessage = "你选的 \(explicitIDs.count) 处会作为主游览点；另补入 \(selected.count - explicitIDs.count) 处顺路停留。"
        } else if explicitIDs.count > targetCount {
            pendingPlanNoticeMessage = "已保留全部 \(explicitIDs.count) 处选择；行程压力会在每天的卡片里标出。"
        } else {
            pendingPlanNoticeMessage = "已按你的选择开始编排行程。"
        }
        await generatePlan()
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
        paceStatusMessage = nil
        let selectionNotice = pendingPlanNoticeMessage
        pendingPlanNoticeMessage = nil
        noticeMessage = nil
        errorMessage = nil
        quoteRefreshState = .idle
        returnTransportOptions = []
        selectedReturnTransportID = nil
        clearLocalTransfers()
        focusedTransportDirection = .outbound
        activityTitle = "正在拾起沿途值得停留的地方"
        activityDetail = "依照目的地、偏好与距离慢慢筛选"
        phase = .discovering

        do {
            let places = if plannedAttractionPlaces.isEmpty {
                try await searchService.discoverPlaces(around: destination, draft: draft)
            } else {
                plannedAttractionPlaces
            }
            guard phase == .discovering else { return }
            activityTitle = "正在编排每天的脚步"
            activityDetail = "正在衡量距离、停留、用餐、休息与夜游时段"
            itineraryDays = routePlanner.orderPlaces(
                places,
                from: destination.coordinate,
                draft: draft
            )
            guard !itineraryDays.isEmpty else { throw PlanningError.placesNotFound }

            phase = .ready
            noticeMessage = selectionNotice
            planReadyFeedbackTrigger += 1
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

    func searchAdditionalPlaces(
        matching query: String,
        interest: TripInterest
    ) async throws -> [TravelPlace] {
        guard let destination else { throw PlanningError.destinationNotFound }
        return try await searchService.searchPlaces(
            matching: query,
            around: destination,
            interest: interest
        )
    }

    func isPlaceIncluded(_ place: TravelPlace) -> Bool {
        containsEquivalentPlace(place)
    }

    @discardableResult
    func addPlace(_ place: TravelPlace, to dayIndex: Int, refreshRoute: Bool = true) -> Bool {
        guard let dayPosition = itineraryDays.firstIndex(where: { $0.index == dayIndex }) else { return false }
        guard !containsEquivalentPlace(place) else {
            noticeMessage = "“\(place.name)”已经在这段旅程里。"
            return false
        }

        rememberItineraryForUndo()
        itineraryDays[dayPosition].stops.append(place)
        selectedDayIndex = dayIndex
        selectedPlaceID = place.id
        itineraryDidChange(
            dayIndex: dayIndex,
            message: "已把“\(place.name)”放进第 \(dayIndex + 1) 天。",
            refreshRoute: refreshRoute
        )
        return true
    }

    func moveStops(
        fromOffsets: IndexSet,
        toOffset: Int,
        in dayIndex: Int,
        refreshRoute: Bool = true
    ) {
        guard !fromOffsets.isEmpty,
              let dayPosition = itineraryDays.firstIndex(where: { $0.index == dayIndex }) else { return }
        let snapshot = currentItinerarySnapshot()
        itineraryDays[dayPosition].stops.move(fromOffsets: fromOffsets, toOffset: toOffset)
        guard itineraryDays != snapshot.days else { return }
        rememberItineraryForUndo(snapshot)
        itineraryDidChange(
            dayIndex: dayIndex,
            message: "第 \(dayIndex + 1) 天的先后次序已经重新排好。",
            refreshRoute: refreshRoute
        )
    }

    func movePlace(
        _ place: TravelPlace,
        by offset: Int,
        in dayIndex: Int,
        refreshRoute: Bool = true
    ) {
        guard let dayPosition = itineraryDays.firstIndex(where: { $0.index == dayIndex }),
              let currentIndex = itineraryDays[dayPosition].stops.firstIndex(where: { $0.id == place.id }) else {
            return
        }
        let targetIndex = currentIndex + offset
        guard itineraryDays[dayPosition].stops.indices.contains(targetIndex) else { return }
        rememberItineraryForUndo()
        let moved = itineraryDays[dayPosition].stops.remove(at: currentIndex)
        itineraryDays[dayPosition].stops.insert(moved, at: targetIndex)
        itineraryDidChange(
            dayIndex: dayIndex,
            message: "“\(place.name)”已经挪到新的顺序。",
            refreshRoute: refreshRoute
        )
    }

    @discardableResult
    func removePlace(
        _ place: TravelPlace,
        from dayIndex: Int,
        refreshRoute: Bool = true
    ) -> Bool {
        guard let dayPosition = itineraryDays.firstIndex(where: { $0.index == dayIndex }),
              itineraryDays[dayPosition].stops.contains(where: { $0.id == place.id }) else {
            return false
        }
        guard itineraryDays[dayPosition].stops.count > 1 else {
            noticeMessage = "每一天至少留下一处停靠；可以先添一个地点，再移走这一处。"
            return false
        }
        rememberItineraryForUndo()
        itineraryDays[dayPosition].stops.removeAll { $0.id == place.id }
        if selectedPlaceID == place.id { selectedPlaceID = nil }
        itineraryDidChange(
            dayIndex: dayIndex,
            message: "已把“\(place.name)”移出第 \(dayIndex + 1) 天。",
            refreshRoute: refreshRoute
        )
        return true
    }

    @discardableResult
    func movePlace(
        _ place: TravelPlace,
        from sourceDayIndex: Int,
        to destinationDayIndex: Int,
        refreshRoute: Bool = true
    ) -> Bool {
        guard sourceDayIndex != destinationDayIndex,
              let sourcePosition = itineraryDays.firstIndex(where: { $0.index == sourceDayIndex }),
              let destinationPosition = itineraryDays.firstIndex(where: { $0.index == destinationDayIndex }),
              let placePosition = itineraryDays[sourcePosition].stops.firstIndex(where: { $0.id == place.id }) else {
            return false
        }
        guard itineraryDays[sourcePosition].stops.count > 1 else {
            noticeMessage = "每一天至少留下一处停靠；可以复制这一站，或先为当天添一个地点。"
            return false
        }
        guard !containsEquivalentPlace(place, in: destinationDayIndex) else {
            noticeMessage = "第 \(destinationDayIndex + 1) 天已经有“\(place.name)”。"
            return false
        }

        rememberItineraryForUndo()
        let movedPlace = itineraryDays[sourcePosition].stops.remove(at: placePosition)
        itineraryDays[destinationPosition].stops.append(movedPlace)
        if selectedPlaceID == place.id { selectedPlaceID = nil }
        itineraryDidChange(
            dayIndices: [sourceDayIndex, destinationDayIndex],
            message: "已把“\(place.name)”移到第 \(destinationDayIndex + 1) 天。",
            refreshRoute: refreshRoute
        )
        return true
    }

    @discardableResult
    func duplicatePlace(
        _ place: TravelPlace,
        from sourceDayIndex: Int,
        to destinationDayIndex: Int,
        refreshRoute: Bool = true
    ) -> TravelPlace? {
        guard sourceDayIndex != destinationDayIndex,
              itineraryDays.contains(where: { day in
                  day.index == sourceDayIndex && day.stops.contains(where: { $0.id == place.id })
              }),
              let destinationPosition = itineraryDays.firstIndex(where: { $0.index == destinationDayIndex }) else {
            return nil
        }
        guard !containsEquivalentPlace(place, in: destinationDayIndex) else {
            noticeMessage = "第 \(destinationDayIndex + 1) 天已经有“\(place.name)”。"
            return nil
        }

        let copiedPlace = TravelPlace(
            name: place.name,
            address: place.address,
            coordinate: place.coordinate,
            interest: place.interest,
            source: place.source
        )
        rememberItineraryForUndo()
        itineraryDays[destinationPosition].stops.append(copiedPlace)
        itineraryDidChange(
            dayIndices: [destinationDayIndex],
            message: "已把“\(place.name)”也放进第 \(destinationDayIndex + 1) 天。",
            refreshRoute: refreshRoute
        )
        return copiedPlace
    }

    func beginItineraryEditing() {
        clearItineraryHistory()
        noticeMessage = nil
        itineraryEditorPresented = true
    }

    func undoItineraryChange(refreshRoute: Bool = true) {
        guard let previous = itineraryUndoStack.popLast() else { return }
        itineraryRedoStack.append(currentItinerarySnapshot())
        restoreItinerarySnapshot(
            previous,
            message: "已撤回上一步，地图也回到先前的安排。",
            refreshRoute: refreshRoute
        )
        syncItineraryHistoryAvailability()
    }

    func redoItineraryChange(refreshRoute: Bool = true) {
        guard let next = itineraryRedoStack.popLast() else { return }
        itineraryUndoStack.append(currentItinerarySnapshot())
        restoreItinerarySnapshot(
            next,
            message: "已重新应用这一步，路线正在跟上。",
            refreshRoute: refreshRoute
        )
        syncItineraryHistoryAvailability()
    }

    func finishItineraryEditing() {
        itineraryEditorPresented = false
        clearItineraryHistory()
        guard itineraryNeedsLogisticsRefresh else { return }
        itineraryNeedsLogisticsRefresh = false
        refreshLogisticsInBackground()
    }

    func applyConditionChanges() {
        persistPlanningDefaults()
        routesByDay = [:]
        failedSegmentsByDay = [:]
        visibleLegCount = 0
        selectedPlaceID = nil
        returnTransportOptions = []
        selectedReturnTransportID = nil
        clearLocalTransfers()
        quoteRefreshState = .stale("日期、人数或出发方式变了，住宿与交通需要重新核价。")
        fitCurrentDay(animated: true)
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
        refreshLogisticsInBackground()
    }

    func handleQuoteRefreshAction() {
        switch quoteRefreshState {
        case .idle, .needsDates:
            conditionsEditorPresented = true
        case .needsService:
            settingsPresented = true
        case .stale, .partial, .noResults, .failed, .updated:
            refreshLogisticsInBackground()
        case .refreshing:
            break
        }
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

    func submitTravelRequest() async {
        let requestText = travelRequestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestText.isEmpty else { return }
        assistantReply = nil

        if assistantSettings.isConfigured {
            isAssistantResponding = true
            defer { isAssistantResponding = false }
            do {
                let interpretation = try await assistantClient.interpret(
                    input: requestText,
                    context: assistantContext,
                    settings: assistantSettings
                )
                assistantReply = interpretation.reply
                assistantFeedbackTrigger += 1
                travelRequestText = ""
                let localIntent = intentParser.parse(requestText)
                let actions = supplementedAssistantActions(
                    interpretation.actions,
                    with: localIntent,
                    rawText: requestText
                )
                if actions.isEmpty {
                    await applyInitialIntent(localIntent, rawText: requestText)
                } else {
                    await applyAssistantActions(actions)
                }
                return
            } catch {
                let localIntent = intentParser.parse(requestText)
                assistantReply = localIntent.isRecognized
                    ? "云端的回声暂时没有抵达，这句话已由本机继续读懂。"
                    : nil
                if localIntent.isRecognized || Self.looksLikeDestination(requestText) {
                    travelRequestText = ""
                    await applyInitialIntent(localIntent, rawText: requestText)
                    return
                }
                noticeMessage = error.localizedDescription
                return
            }
        }

        await applyInitialIntent(intentParser.parse(requestText), rawText: requestText)
    }

    private func supplementedAssistantActions(
        _ assistantActions: [TravelAssistantAction],
        with intent: AdjustmentIntent,
        rawText: String
    ) -> [TravelAssistantAction] {
        var result = assistantActions
        var existingTypes = Set(result.map { $0.type.rawValue })
        func append(_ type: TravelAssistantActionType, _ value: String?) {
            guard !existingTypes.contains(type.rawValue), let value, !value.isEmpty else { return }
            result.append(TravelAssistantAction(type: type, value: value))
            existingTypes.insert(type.rawValue)
        }

        let fallbackDestination = intent.destination
            ?? (Self.looksLikeDestination(rawText) ? rawText.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        append(.setDestination, fallbackDestination)
        append(.setOrigin, intent.origin)
        append(.setPace, intent.pace?.rawValue)
        append(.setTravelMode, intent.travelMode?.rawValue)
        append(.setLongDistanceMode, intent.longDistanceMode?.rawValue)
        append(.setDayCount, intent.dayCount.map(String.init))
        append(.setTravelers, intent.travelers.map(String.init))
        append(.setBudget, intent.budgetPerPerson.map(String.init))
        append(.setStartDate, intent.startDate.map { Self.assistantDayFormatter.string(from: $0) })
        append(.setEndDate, intent.endDate.map { Self.assistantDayFormatter.string(from: $0) })
        append(.setAccommodationMaxPrice, intent.accommodationMaxPrice.map(String.init))
        append(.setAccommodationSort, intent.accommodationSort?.rawValue)
        for interest in intent.addedInterests where !existingTypes.contains(TravelAssistantActionType.addInterest.rawValue) {
            result.append(.init(type: .addInterest, value: interest.rawValue))
        }
        for interest in intent.removedInterests where !existingTypes.contains(TravelAssistantActionType.removeInterest.rawValue) {
            result.append(.init(type: .removeInterest, value: interest.rawValue))
        }
        if intent.shouldGeneratePlan { append(.generatePlan, "true") }
        return Array(result.prefix(20))
    }

    private func applyInitialIntent(_ intent: AdjustmentIntent, rawText: String) async {
        if let destination = intent.destination {
            draft.destination = destination
        } else if Self.looksLikeDestination(rawText) {
            draft.destination = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let origin = intent.origin { draft.logistics.origin = origin }
        if let pace = intent.pace { draft.pace = pace }
        if let travelMode = intent.travelMode { draft.travelMode = travelMode }
        if let longDistanceMode = intent.longDistanceMode {
            draft.logistics.preferredLongDistanceMode = longDistanceMode
        }
        if let dayCount = intent.dayCount { draft.dayCount = dayCount }
        if let travelers = intent.travelers { draft.logistics.travelers = travelers }
        if let budget = intent.budgetPerPerson { draft.budgetPerPerson = min(max(budget, 1_000), 30_000) }
        if let maximum = intent.accommodationMaxPrice { accommodationMaxNightlyPrice = maximum }
        if let sort = intent.accommodationSort { accommodationSort = sort }
        draft.interests.formUnion(intent.addedInterests)
        draft.interests.subtract(intent.removedInterests)
        if draft.interests.isEmpty { draft.interests = [.gardens] }

        if let startDate = intent.startDate {
            draft.logistics.startDate = startDate
            draft.logistics.endDate = intent.endDate
                ?? Calendar.current.date(byAdding: .day, value: max(draft.dayCount - 1, 1), to: startDate)
            if let endDate = draft.logistics.endDate { updateEndDate(endDate) }
        }

        guard canContinueDestination else {
            noticeMessage = "我听见了旅途偏好，还需要一个能在地图上落下的目的地。"
            return
        }
        travelRequestText = ""
        await resolveDestination()
        if intent.shouldGeneratePlan, phase == .preferences {
            await generatePlan()
        } else if let assistantReply {
            noticeMessage = assistantReply
        }
    }

    func applyAdjustment() async {
        let requestText = adjustmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestText.isEmpty else { return }
        assistantReply = nil

        if assistantSettings.isConfigured {
            isAssistantResponding = true
            defer { isAssistantResponding = false }
            do {
                let interpretation = try await assistantClient.interpret(
                    input: requestText,
                    context: assistantContext,
                    settings: assistantSettings
                )
                assistantReply = interpretation.reply
                assistantFeedbackTrigger += 1
                adjustmentText = ""
                if interpretation.actions.isEmpty {
                    let localIntent = intentParser.parse(requestText)
                    if localIntent.isRecognized {
                        await applyDeterministicAdjustment(requestText)
                    } else {
                        noticeMessage = interpretation.reply
                    }
                } else {
                    await applyAssistantActions(interpretation.actions)
                }
                return
            } catch {
                let localIntent = intentParser.parse(requestText)
                assistantReply = "云端的回声暂时没有抵达。\(localIntent.isRecognized ? "这一步已由本机继续完成。" : "你仍可在设置里检查服务。")"
                if localIntent.isRecognized {
                    await applyDeterministicAdjustment(requestText)
                    return
                }
                noticeMessage = error.localizedDescription
                return
            }
        }

        await applyDeterministicAdjustment(requestText)
    }

    private func applyDeterministicAdjustment(_ requestText: String) async {
        let intent = intentParser.parse(requestText)
        guard intent.isRecognized else {
            noticeMessage = "这句话需要智能向导来听懂；可以先在设置里接通服务，或试试“轻松一点”“公交优先”。"
            return
        }

        let onlyRequestsRelaxedPace = intent.pace == .relaxed
            && intent.destination == nil
            && intent.origin == nil
            && intent.travelMode == nil
            && intent.longDistanceMode == nil
            && intent.dayCount == nil
            && intent.travelers == nil
            && intent.budgetPerPerson == nil
            && intent.startDate == nil
            && intent.endDate == nil
            && intent.accommodationMaxPrice == nil
            && intent.accommodationSort == nil
            && !intent.shouldGeneratePlan
            && intent.addedInterests.isEmpty
            && intent.removedInterests.isEmpty
            && intent.excludedPlaceTerm == nil
        if phase == .ready, onlyRequestsRelaxedPace {
            adjustmentText = ""
            relaxCurrentPlan()
            return
        }

        let wasReady = phase == .ready
        var planNeedsRegeneration = false
        var logisticsNeedRefresh = false
        var filtersChanged = false

        if let destination = intent.destination, destination != draft.destination {
            draft.destination = destination
            self.destination = nil
            adjustmentText = ""
            await resolveDestination()
            if (wasReady || intent.shouldGeneratePlan), phase == .preferences { await generatePlan() }
            return
        }
        if let origin = intent.origin {
            draft.logistics.origin = origin
            logisticsNeedRefresh = true
        }
        if let pace = intent.pace {
            draft.pace = pace
            planNeedsRegeneration = true
        }
        if let travelMode = intent.travelMode {
            draft.travelMode = travelMode
            planNeedsRegeneration = true
        }
        if let longDistanceMode = intent.longDistanceMode {
            draft.logistics.preferredLongDistanceMode = longDistanceMode
            logisticsNeedRefresh = true
        }
        if let dayCount = intent.dayCount {
            adjustDayCount(by: dayCount - draft.dayCount)
            planNeedsRegeneration = true
        }
        if let travelers = intent.travelers {
            draft.logistics.travelers = travelers
            logisticsNeedRefresh = true
        }
        if let budget = intent.budgetPerPerson { draft.budgetPerPerson = budget }
        if let maximum = intent.accommodationMaxPrice {
            accommodationMaxNightlyPrice = maximum
            filtersChanged = true
        }
        if let sort = intent.accommodationSort {
            accommodationSort = sort
            filtersChanged = true
        }
        if let startDate = intent.startDate {
            draft.logistics.startDate = startDate
            draft.logistics.endDate = intent.endDate
                ?? Calendar.current.date(byAdding: .day, value: max(draft.dayCount - 1, 1), to: startDate)
            if let endDate = draft.logistics.endDate { updateEndDate(endDate) }
            logisticsNeedRefresh = true
        }
        draft.interests.formUnion(intent.addedInterests)
        draft.interests.subtract(intent.removedInterests)
        if draft.interests.isEmpty { draft.interests = [.gardens] }
        if !intent.addedInterests.isEmpty || !intent.removedInterests.isEmpty {
            planNeedsRegeneration = true
        }

        if let excludedTerm = intent.excludedPlaceTerm {
            let originalCount = itineraryDays.reduce(0) { $0 + $1.stops.count }
            let filteredDays = itineraryDays.compactMap { day in
                var updated = day
                updated.stops.removeAll {
                    $0.name.localizedCaseInsensitiveContains(excludedTerm)
                }
                return updated.stops.isEmpty ? nil : updated
            }
            itineraryDays = filteredDays.enumerated().map { index, day in
                ItineraryDay(index: index, stops: day.stops)
            }
            let updatedCount = itineraryDays.reduce(0) { $0 + $1.stops.count }

            if updatedCount < originalCount {
                routesByDay = [:]
                failedSegmentsByDay = [:]
                selectedDayIndex = itineraryDays.first?.index ?? 0
                adjustmentText = ""
                noticeMessage = "已移除包含“\(excludedTerm)”的地点。"
                quoteRefreshState = .stale("景点分布变了，住处距离与接驳方式需要重新丈量。")
                fitCurrentDay(animated: true)
                await loadRoutesForSelectedDay(reveal: true)
                refreshLogisticsInBackground()
                return
            }

            noticeMessage = "当前路线里没有找到“\(excludedTerm)”。"
            return
        }

        adjustmentText = ""
        if intent.shouldGeneratePlan || (planNeedsRegeneration && phase == .ready) {
            await generatePlan()
        } else {
            if logisticsNeedRefresh, phase == .ready { refreshLogisticsInBackground() }
            if filtersChanged, phase == .ready {
                planMapFocus = .accommodation
                fitCoordinates(filteredAccommodations.prefix(12).map(\.coordinate), animated: true)
            }
            noticeMessage = "已经照这句话调整，地图会沿新的条件重新展开。"
        }
    }

    private func applyAssistantActions(_ actions: [TravelAssistantAction]) async {
        var routesNeedRefresh = false
        var logisticsNeedRefresh = false
        var planNeedsRegeneration = false
        var destinationChanged = false
        var shouldGeneratePlan = false
        var accommodationFilterChanged = false
        var requestedRelaxation = false
        var placeToFocus: TravelPlace?

        for action in actions {
            switch action.type {
            case .setDestination:
                let value = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                destinationChanged = destinationChanged || value != draft.destination
                draft.destination = value
                if destinationChanged { destination = nil }
            case .setOrigin:
                draft.logistics.origin = action.value
                logisticsNeedRefresh = phase == .ready
            case .setPace:
                guard let pace = TripPace(rawValue: action.value) else { continue }
                if pace == .relaxed, phase == .ready {
                    requestedRelaxation = true
                } else {
                    draft.pace = pace
                    paceStatusMessage = nil
                    planNeedsRegeneration = phase == .ready
                }
            case .setTravelMode:
                guard let mode = TravelMode(rawValue: action.value), mode != draft.travelMode else { continue }
                draft.travelMode = mode
                routesNeedRefresh = phase == .ready
            case .setLongDistanceMode:
                draft.logistics.preferredLongDistanceMode = action.value == "auto"
                    ? nil
                    : LongDistanceMode(rawValue: action.value)
                logisticsNeedRefresh = phase == .ready
            case .setDayCount:
                guard let value = Int(action.value) else { continue }
                let next = min(max(value, 1), 7)
                adjustDayCount(by: next - draft.dayCount)
                planNeedsRegeneration = phase == .ready
            case .setTravelers:
                guard let value = Int(action.value) else { continue }
                draft.logistics.travelers = min(max(value, 1), 8)
                logisticsNeedRefresh = phase == .ready
            case .setBudget:
                guard let budget = Int(action.value) else { continue }
                draft.budgetPerPerson = min(max(budget, 1_000), 30_000)
            case .setStartDate:
                guard let date = Self.assistantDayFormatter.date(from: action.value) else { continue }
                if draft.logistics.endDate == nil { setDatesEnabled(true) }
                updateStartDate(date)
                logisticsNeedRefresh = phase == .ready
            case .setEndDate:
                guard let date = Self.assistantDayFormatter.date(from: action.value) else { continue }
                if draft.logistics.startDate == nil {
                    draft.logistics.startDate = Calendar.current.startOfDay(for: .now)
                }
                updateEndDate(date)
                logisticsNeedRefresh = phase == .ready
            case .setAccommodationMaxPrice:
                guard let value = Int(action.value) else { continue }
                accommodationMaxNightlyPrice = min(max(value, 100), 10_000)
                planMapFocus = phase == .ready ? .accommodation : planMapFocus
                accommodationFilterChanged = phase == .ready
            case .setAccommodationSort:
                guard let sort = AccommodationSort(rawValue: action.value) else { continue }
                accommodationSort = sort
                planMapFocus = phase == .ready ? .accommodation : planMapFocus
                accommodationFilterChanged = phase == .ready
            case .addInterest:
                guard let interest = TripInterest(rawValue: action.value) else { continue }
                draft.interests.insert(interest)
                planNeedsRegeneration = phase == .ready
            case .removeInterest:
                guard let interest = TripInterest(rawValue: action.value), draft.interests.count > 1 else { continue }
                draft.interests.remove(interest)
                planNeedsRegeneration = phase == .ready
            case .generatePlan:
                shouldGeneratePlan = action.value.lowercased() == "true"
            case .focusPlace:
                placeToFocus = itineraryDays.flatMap(\.stops).first { $0.name == action.value }
            case .removePlace:
                guard let day = itineraryDays.first(where: { day in
                    day.stops.contains(where: { $0.name == action.value })
                }), let place = day.stops.first(where: { $0.name == action.value }) else { continue }
                if removePlace(place, from: day.index, refreshRoute: false) {
                    routesNeedRefresh = true
                    logisticsNeedRefresh = true
                }
            }
        }

        if destinationChanged {
            await resolveDestination()
            if shouldGeneratePlan, phase == .preferences { await generatePlan() }
            if let assistantReply { noticeMessage = assistantReply }
            return
        }

        if shouldGeneratePlan {
            await generatePlan()
            if let assistantReply { noticeMessage = assistantReply }
            return
        }

        if planNeedsRegeneration, phase == .ready, !requestedRelaxation {
            await generatePlan()
            if let assistantReply { noticeMessage = assistantReply }
            return
        }

        if requestedRelaxation {
            relaxCurrentPlan()
        }

        if routesNeedRefresh, phase == .ready {
            routeTask?.cancel()
            revealTask?.cancel()
            routesByDay = [:]
            failedSegmentsByDay = [:]
            visibleLegCount = 0
            selectedPlaceID = nil
            fitCurrentDay(animated: true)
            await loadRoutesForSelectedDay(reveal: true)
        }
        if logisticsNeedRefresh, !requestedRelaxation {
            refreshLogisticsInBackground()
        }
        if accommodationFilterChanged {
            fitCoordinates(filteredAccommodations.prefix(12).map(\.coordinate), animated: true)
        }

        if let placeToFocus,
           let day = itineraryDays.first(where: { $0.stops.contains(where: { $0.id == placeToFocus.id }) }) {
            selectedDayIndex = day.index
            selectPlace(placeToFocus)
        }
        persistPlanningDefaults()
        if let assistantReply { noticeMessage = assistantReply }
    }

    func testAssistantConnection() async -> String {
        guard assistantSettings.isConfigured else {
            return assistantSettings.mode == .managed
                ? "先填写并接通 AnyTravel 伴随服务地址。"
                : "请补齐服务地址、模型名，并把 API Key 存入钥匙串。"
        }
        do {
            let result = try await assistantClient.interpret(
                input: "只确认服务已经接通，不要修改行程。",
                context: assistantContext,
                settings: assistantSettings
            )
            return "已接通 \(result.model ?? assistantSettings.customModel)：\(result.reply)"
        } catch {
            return error.localizedDescription
        }
    }

    private var assistantContext: TravelAssistantContext {
        TravelAssistantContext(
            destination: destination?.title ?? draft.destination,
            dayCount: max(draft.dayCount, itineraryDays.count),
            budgetPerPerson: draft.budgetPerPerson,
            pace: draft.pace.rawValue,
            travelMode: draft.travelMode.rawValue,
            selectedDayIndex: selectedDayIndex,
            interests: draft.interests.map(\.rawValue).sorted(),
            places: itineraryDays.flatMap { day in
                day.stops.map {
                    TravelAssistantPlaceContext(
                        name: $0.name,
                        dayIndex: day.index,
                        interest: $0.interest.rawValue
                    )
                }
            },
            origin: draft.logistics.origin,
            travelers: draft.logistics.travelers,
            startDate: draft.logistics.startDate.map { Self.assistantDayFormatter.string(from: $0) },
            endDate: draft.logistics.endDate.map { Self.assistantDayFormatter.string(from: $0) },
            longDistanceMode: draft.logistics.preferredLongDistanceMode?.rawValue,
            accommodationMaxNightlyPrice: accommodationMaxNightlyPrice,
            accommodationSort: accommodationSort.rawValue
        )
    }

    func relaxCurrentPlan() {
        guard phase == .ready, !itineraryDays.isEmpty else { return }
        let previousDayCount = itineraryDays.count
        let totalStops = itineraryDays.reduce(0) { $0 + $1.stops.count }
        let result = planPacingService.makeRelaxedItinerary(
            from: itineraryDays,
            travelMinutesByDay: routeTravelMinutesByDay,
            failedSegmentsByDay: failedSegmentsByDay,
            pace: draft.pace,
            mode: draft.travelMode,
            constraintsByDay: tourismConstraintsByDay
        )
        let didChange = draft.pace != .relaxed || result.days != itineraryDays
        guard didChange else {
            noticeMessage = "这段行程已经很松弛了，午餐与休息都留有余地。"
            return
        }

        routeTask?.cancel()
        revealTask?.cancel()
        draft.pace = .relaxed
        draft.dayCount = result.days.count
        let relaxedStops = result.days.flatMap(\.stops)
        if let planningCenter = destination?.coordinate ?? relaxedStops.first?.coordinate {
            itineraryDays = routePlanner.orderPlaces(
                relaxedStops,
                from: planningCenter,
                draft: draft
            )
        } else {
            itineraryDays = result.days
        }
        selectedDayIndex = min(selectedDayIndex, max(result.days.count - 1, 0))
        selectedPlaceID = nil
        routesByDay = [:]
        failedSegmentsByDay = [:]
        visibleLegCount = 0
        if let startDate = draft.logistics.startDate, result.days.count != previousDayCount {
            draft.logistics.endDate = Calendar.current.date(
                byAdding: .day,
                value: max(result.days.count - 1, 0),
                to: startDate
            )
            returnTransportOptions = []
            selectedReturnTransportID = nil
        }
        clearLocalTransfers()
        clearItineraryHistory()
        quoteRefreshState = .stale("行程节奏与日期变了，住宿晚数、返程和接驳需要重新核价。")
        itineraryNeedsLogisticsRefresh = false
        persistPlanningDefaults()
        paceFeedbackTrigger += 1

        if result.stillBusy {
            paceStatusMessage = "已尽量铺开 \(totalStops) 处停留；七天内仍有一天超过两处，可以在路线编辑器里继续取舍。"
        } else if result.days.count > previousDayCount {
            paceStatusMessage = "已把 \(totalStops) 处停留从 \(previousDayCount) 天铺成 \(result.days.count) 天；返程与住宿正在重新核价。"
        } else {
            paceStatusMessage = "已把每天的时刻改成松弛节奏，路线与住宿距离正在重新丈量。"
        }
        noticeMessage = paceStatusMessage

        fitCurrentDay(animated: true)
        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
        refreshLogisticsInBackground()
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
                selectedTransportID: selectedTransportID,
                returnTransportOptions: returnTransportOptions,
                selectedReturnTransportID: selectedReturnTransportID,
                outboundTransferOptions: outboundTransferOptions,
                selectedOutboundTransferID: selectedOutboundTransferID,
                returnTransferOptions: returnTransferOptions,
                selectedReturnTransferID: selectedReturnTransferID
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

    func exportCurrentPlan(_ format: PlanExportFormat) {
        guard phase == .ready, !itineraryDays.isEmpty else {
            errorMessage = PlanExportError.noItinerary.localizedDescription
            return
        }
        if format != .pdf, !canExportCalendar {
            errorMessage = PlanExportError.missingDates.localizedDescription
            return
        }

        exportTask?.cancel()
        let payload = currentExportPayload()
        isExportingPlan = true
        exportStatusMessage = format == .calendar ? "正在把每天的时刻写进日历" : "正在把地图与行程折成随身文件"
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isExportingPlan = false }
            do {
                let urls = try await self.planExportService.export(format, payload: payload)
                guard !Task.isCancelled else { return }
                self.exportStatusMessage = nil
                self.noticeMessage = urls.count == 1
                    ? "行程文件已经整理好，正在打开分享。"
                    : "PDF 与日历已经整理好，正在打开分享。"
                self.sharePayload = PlanSharePayload(title: payload.title, urls: urls)
                self.exportFeedbackTrigger += 1
            } catch is CancellationError {
                return
            } catch {
                self.exportStatusMessage = nil
                self.errorMessage = error.localizedDescription
            }
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
            returnTransportOptions = snapshot.returnTransportOptions ?? []
            selectedReturnTransportID = snapshot.selectedReturnTransportID
            outboundTransferOptions = snapshot.outboundTransferOptions ?? []
            selectedOutboundTransferID = snapshot.selectedOutboundTransferID
            returnTransferOptions = snapshot.returnTransferOptions ?? []
            selectedReturnTransferID = snapshot.selectedReturnTransferID
            transferRoutesByOptionID = [:]
            let snapshotPoints = (snapshot.transportOptions + returnTransportOptions).compactMap(\.arrivalAccessPoint)
                + snapshot.accommodations.flatMap { Array($0.nearestAccessPoints.values) }
            accessPoints = snapshotPoints.reduce(into: []) { points, point in
                guard !points.contains(where: { $0.name == point.name && $0.kind == point.kind }) else { return }
                points.append(point)
            }
        } else {
            accommodations = []
            selectedAccommodationID = nil
            accessPoints = []
            transportOptions = []
            selectedTransportID = nil
            returnTransportOptions = []
            selectedReturnTransportID = nil
            outboundTransferOptions = []
            selectedOutboundTransferID = nil
            returnTransferOptions = []
            selectedReturnTransferID = nil
            transferRoutesByOptionID = [:]
        }
        originResolution = nil
        focusedTransportDirection = .outbound
        destination = DestinationResolution(
            title: trip.draft.destination,
            coordinate: trip.destinationCenter,
            region: MKCoordinateRegion(
                center: trip.destinationCenter.clLocationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.24)
            )
        )
        phase = .ready
        quoteRefreshState = .stale("正在复核旅册里留下的价格与班次。")
        libraryPresented = false
        fitCurrentDay(animated: true)
        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
        refreshLogisticsInBackground()
    }

    private func currentExportPayload() -> PlanExportPayload {
        let exportDays = itineraryDays.map { day in
            let date = draft.logistics.startDate.flatMap {
                Calendar.current.date(byAdding: .day, value: day.index, to: $0)
            }
            let segments = (routesByDay[day.index] ?? []).map {
                Self.coordinates(from: $0.route.polyline)
            }
            return PlanExportDay(
                itinerary: day,
                date: date,
                schedule: scheduleBuilder.build(
                    for: day,
                    pace: draft.pace,
                    accommodation: selectedAccommodation,
                    travelMode: draft.travelMode,
                    constraints: tourismConstraints(for: day)
                ),
                routeSegments: segments
            )
        }
        let destinationName = destination?.title ?? draft.destination
        return PlanExportPayload(
            title: "\(destinationName) · \(draft.dayCount)天旅行方案",
            draft: draft,
            days: exportDays,
            accommodation: selectedAccommodation,
            outboundTransport: selectedTransport,
            returnTransport: selectedReturnTransport,
            outboundTransfer: selectedOutboundTransfer,
            returnTransfer: selectedReturnTransfer,
            expenses: expenseLines,
            generatedAt: .now
        )
    }

    private static func coordinates(from polyline: MKPolyline) -> [Coordinate] {
        guard polyline.pointCount > 0 else { return [] }
        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates.map(Coordinate.init)
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

    func adjustDayCount(by delta: Int) {
        let nextValue = min(max(draft.dayCount + delta, 1), 7)
        guard nextValue != draft.dayCount else { return }
        draft.dayCount = nextValue
        guard let start = draft.logistics.startDate else { return }
        draft.logistics.endDate = Calendar.current.date(
            byAdding: .day,
            value: max(nextValue - 1, 1),
            to: start
        )
    }

    func adjustStartDate(by dayOffset: Int) {
        guard let currentStart = draft.logistics.startDate else { return }
        let calendar = Calendar.current
        let earliest = calendar.startOfDay(for: .now)
        let proposed = calendar.date(byAdding: .day, value: dayOffset, to: currentStart) ?? currentStart
        let nextStart = max(calendar.startOfDay(for: proposed), earliest)
        let currentEnd = draft.logistics.endDate ?? currentStart
        let span = max(calendar.dateComponents([.day], from: currentStart, to: currentEnd).day ?? 1, 1)
        draft.logistics.startDate = nextStart
        draft.logistics.endDate = calendar.date(byAdding: .day, value: span, to: nextStart)
    }

    func adjustEndDate(by dayOffset: Int) {
        guard let currentEnd = draft.logistics.endDate,
              let proposed = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentEnd)
        else { return }
        updateEndDate(proposed)
    }

    func updateStartDate(_ date: Date) {
        let calendar = Calendar.current
        let oldStart = draft.logistics.startDate
        let oldEnd = draft.logistics.endDate
        let start = max(calendar.startOfDay(for: date), calendar.startOfDay(for: .now))
        let preservedSpan = if let oldStart, let oldEnd {
            max(calendar.dateComponents([.day], from: oldStart, to: oldEnd).day ?? 1, 1)
        } else {
            max(draft.dayCount - 1, 1)
        }
        draft.logistics.startDate = start
        draft.logistics.endDate = calendar.date(byAdding: .day, value: preservedSpan, to: start)
    }

    func updateEndDate(_ date: Date) {
        guard let start = draft.logistics.startDate else {
            draft.logistics.endDate = date
            return
        }
        let calendar = Calendar.current
        let minimumEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let maximumEnd = calendar.date(byAdding: .day, value: 6, to: start) ?? date
        let end = min(max(calendar.startOfDay(for: date), minimumEnd), maximumEnd)
        draft.logistics.endDate = end
        let nights = calendar.dateComponents([.day], from: start, to: end).day ?? 1
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

        let wantsLiveQuotes = draft.logistics.hasDates
        let trimmedOrigin = draft.logistics.origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAccommodationPriceSource = pricingBackendClient.isConfigured || rollingGoDirectClient.isConfigured
        let hasTransportPriceSource = !draft.logistics.skipTransport && !trimmedOrigin.isEmpty
        let hasAnyPriceSource = hasAccommodationPriceSource || hasTransportPriceSource
        let canRequestAccommodationQuotes = wantsLiveQuotes && hasAccommodationPriceSource
        let canRequestBackendQuotes = wantsLiveQuotes && pricingBackendClient.isConfigured
        let canRequestTransportQuotes = wantsLiveQuotes && hasTransportPriceSource
        if !wantsLiveQuotes {
            quoteRefreshState = .needsDates
        } else if !hasAnyPriceSource {
            quoteRefreshState = .needsService
        } else {
            quoteRefreshState = .refreshing
        }

        var receivedQuoteCount = 0
        var latestCapture: Date?
        var allResultsCached = true
        var pricingIssues: [String] = []
        var pricingFailures: [String] = []
        if wantsLiveQuotes, !draft.logistics.skipAccommodation, !hasAccommodationPriceSource {
            pricingIssues.append("住宿实时价源尚未连接；交通仍会继续查询")
        }

        if pricingBackendClient.isConfigured {
            logisticsStatusMessage = "正在复核景点门票与预约"
            do {
                let result = try await pricingBackendClient.enrichTicketQuotes(
                    itineraryDays,
                    destination: draft.destination,
                    visitDate: draft.logistics.startDate
                )
                guard !Task.isCancelled else { return }
                if UIAccessibility.isReduceMotionEnabled {
                    itineraryDays = result.value
                } else {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                        itineraryDays = result.value
                    }
                }
                receivedQuoteCount += result.receivedCount
                latestCapture = max(latestCapture ?? result.capturedAt, result.capturedAt)
                allResultsCached = allResultsCached && result.isCached
                pricingIssues.append(contentsOf: result.issues.map(\.message))
            } catch {
                if wantsLiveQuotes {
                    pricingFailures.append(Self.pricingFailureText(error))
                }
            }
        }

        if draft.logistics.skipAccommodation {
            accommodations = []
            selectedAccommodationID = nil
            accessPoints = await logisticsSearchService.discoverAccessPoints(
                around: destination,
                destinationName: draft.destination
            )
        } else {
            let previousName = selectedAccommodation?.name
            var discovery = await logisticsSearchService.discoverAccommodations(
                around: destination,
                itineraryDays: itineraryDays,
                draft: draft
            )
            guard !Task.isCancelled else { return }
            logisticsStatusMessage = draft.logistics.hasDates ? "正在把当天的住宿价格带回来" : "正在沿景点整理合适的落脚处"
            if canRequestAccommodationQuotes {
                let anchors = itineraryDays.compactMap { $0.stops.first?.name }
                var backendReturnedRollingGoPrice = false
                if pricingBackendClient.isConfigured {
                    do {
                        let catalog = try await pricingBackendClient.searchAccommodationCatalog(
                            destination: draft.destination,
                            logistics: draft.logistics,
                            anchors: anchors
                        )
                        discovery = await logisticsSearchService.mergingCatalog(
                            catalog.value,
                            into: discovery,
                            around: destination,
                            itineraryDays: itineraryDays,
                            draft: draft
                        )
                        backendReturnedRollingGoPrice = catalog.value
                            .flatMap(\.quotes)
                            .contains { $0.provider == .rollingGo && $0.amountCNY != nil }
                        receivedQuoteCount += catalog.receivedCount
                        latestCapture = max(latestCapture ?? catalog.capturedAt, catalog.capturedAt)
                        allResultsCached = allResultsCached && catalog.isCached
                        pricingIssues.append(contentsOf: catalog.issues.map(\.message))
                    } catch {
                        pricingFailures.append(Self.pricingFailureText(error))
                    }
                }

                // A stale or unreachable companion URL must never disable the
                // embedded hotel source. Skip the second call only when the
                // companion already delivered a concrete RollingGo price.
                if rollingGoDirectClient.isConfigured, !backendReturnedRollingGoPrice {
                    do {
                        let catalog = try await rollingGoDirectClient.searchAccommodationCatalog(
                            destination: draft.destination,
                            logistics: draft.logistics,
                            anchors: anchors
                        )
                        discovery = await logisticsSearchService.mergingCatalog(
                            catalog.value,
                            into: discovery,
                            around: destination,
                            itineraryDays: itineraryDays,
                            draft: draft
                        )
                        receivedQuoteCount += catalog.receivedCount
                        latestCapture = max(latestCapture ?? catalog.capturedAt, catalog.capturedAt)
                        allResultsCached = allResultsCached && catalog.isCached
                        pricingIssues.append(contentsOf: catalog.issues.map(\.message))
                    } catch {
                        pricingFailures.append(Self.pricingFailureText(error))
                    }
                }
            }
            var updatedAccommodations = discovery.options
            if canRequestBackendQuotes {
                do {
                    let result = try await pricingBackendClient.enrichAccommodationQuotes(
                        updatedAccommodations,
                        destination: draft.destination,
                        logistics: draft.logistics
                    )
                    updatedAccommodations = result.value
                    receivedQuoteCount += result.receivedCount
                    latestCapture = max(latestCapture ?? result.capturedAt, result.capturedAt)
                    allResultsCached = allResultsCached && result.isCached
                    pricingIssues.append(contentsOf: result.issues.map(\.message))
                } catch {
                    pricingFailures.append(Self.pricingFailureText(error))
                }
            }
            guard !Task.isCancelled else { return }
            if UIAccessibility.isReduceMotionEnabled {
                accommodations = updatedAccommodations
            } else {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    accommodations = updatedAccommodations
                }
            }
            accessPoints = discovery.accessPoints
            selectedAccommodationID = accommodations.first(where: { $0.name == previousName })?.id
                ?? accommodations.first?.id
        }

        logisticsStatusMessage = "正在把抵达方式与落脚处接在一起"
        originResolution = nil
        if !trimmedOrigin.isEmpty {
            originResolution = try? await searchService.resolveDestination(trimmedOrigin)
        }
        guard !Task.isCancelled else { return }
        rebuildTransportOptions()
        if canRequestTransportQuotes {
            logisticsStatusMessage = "正在读取班次、余票与这一刻的价格"
            do {
                let result = try await refreshTransportQuotes()
                receivedQuoteCount += result.receivedCount
                latestCapture = max(latestCapture ?? result.capturedAt, result.capturedAt)
                allResultsCached = allResultsCached && result.isCached
                pricingIssues.append(contentsOf: result.issues.map(\.message))
            } catch {
                pricingFailures.append(Self.pricingFailureText(error))
            }
        }

        logisticsStatusMessage = "正在把车站与住处之间的路接起来"
        await refreshLocalTransfers()

        if wantsLiveQuotes, !draft.logistics.skipTransport, trimmedOrigin.isEmpty {
            pricingIssues.append("补充出发地后，才能读取班次与交通价格")
        }

        guard !Task.isCancelled else { return }
        let issueMessage = Self.firstUniqueMessages(in: pricingIssues).joined(separator: "；")
        let failureMessage = Self.firstUniqueMessages(in: pricingFailures).joined(separator: "；")
        if wantsLiveQuotes, hasAnyPriceSource {
            if receivedQuoteCount > 0, (!failureMessage.isEmpty || !issueMessage.isEmpty) {
                quoteRefreshState = .partial(
                    capturedAt: latestCapture,
                    count: receivedQuoteCount,
                    message: [failureMessage, issueMessage].filter { !$0.isEmpty }.joined(separator: "；")
                )
            } else if receivedQuoteCount > 0, let latestCapture {
                quoteRefreshState = .updated(
                    capturedAt: latestCapture,
                    count: receivedQuoteCount,
                    cached: allResultsCached
                )
            } else if !failureMessage.isEmpty {
                quoteRefreshState = .failed(failureMessage)
            } else {
                quoteRefreshState = .noResults(
                    capturedAt: latestCapture,
                    message: issueMessage.isEmpty ? "渠道没有返回匹配的房型或班次，可以稍后再试。" : issueMessage
                )
            }
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
        returnTransportOptions = []
        selectedReturnTransportID = nil
        clearLocalTransfers()
        rebuildTransportOptions()
        if draft.logistics.hasDates,
           !draft.logistics.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !draft.logistics.skipTransport {
            logisticsTask?.cancel()
            logisticsTask = Task { [weak self] in
                guard let self else { return }
                self.isLogisticsLoading = true
                self.logisticsStatusMessage = "正在从新住处重新丈量抵达的路"
                self.quoteRefreshState = .refreshing
                do {
                    let result = try await self.refreshTransportQuotes()
                    let issues = result.issues.map(\.message).joined(separator: "；")
                    if result.receivedCount > 0, issues.isEmpty {
                        self.quoteRefreshState = .updated(
                            capturedAt: result.capturedAt,
                            count: result.receivedCount,
                            cached: result.isCached
                        )
                    } else if result.receivedCount > 0 {
                        self.quoteRefreshState = .partial(
                            capturedAt: result.capturedAt,
                            count: result.receivedCount,
                            message: issues
                        )
                    } else {
                        self.quoteRefreshState = .noResults(
                            capturedAt: result.capturedAt,
                            message: issues.isEmpty ? "当前住处暂时没有匹配的交通报价。" : issues
                        )
                    }
                } catch {
                    self.quoteRefreshState = .failed(Self.pricingFailureText(error))
                }
                await self.refreshLocalTransfers()
                self.isLogisticsLoading = false
                self.logisticsStatusMessage = nil
            }
        } else {
            refreshLocalTransfersInBackground()
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
        focusedTransportDirection = option.journeyDirection
        if option.journeyDirection == .returnTrip {
            selectedReturnTransportID = option.id
        } else {
            selectedTransportID = option.id
        }
        if let accessPoint = option.arrivalAccessPoint {
            fitCoordinates(
                [accessPoint.coordinate, selectedAccommodation?.coordinate].compactMap { $0 },
                animated: true
            )
        }
        refreshLocalTransfersInBackground()
    }

    func setTransportDirectionFocus(_ direction: TransportDirection) {
        focusedTransportDirection = direction
        let transfer = direction == .outbound ? selectedOutboundTransfer : selectedReturnTransfer
        if let route = transfer.flatMap({ transferRoutesByOptionID[$0.id] }) {
            setCamera(.rect(padded(route.polyline.boundingMapRect)), animated: true)
            return
        }
        let transport = direction == .outbound ? selectedTransport : selectedReturnTransport
        let coordinates = [transport?.arrivalAccessPoint?.coordinate, selectedAccommodation?.coordinate]
            .compactMap { $0 }
        if !coordinates.isEmpty { fitCoordinates(coordinates, animated: true) }
    }

    func selectLocalTransfer(_ option: LocalTransferOption) {
        focusedTransportDirection = option.direction
        if option.direction == .outbound {
            selectedOutboundTransferID = option.id
        } else {
            selectedReturnTransferID = option.id
        }
        if let route = transferRoutesByOptionID[option.id] {
            setCamera(.rect(padded(route.polyline.boundingMapRect)), animated: true)
        } else {
            let transport = option.direction == .outbound ? selectedTransport : selectedReturnTransport
            fitCoordinates(
                [transport?.arrivalAccessPoint?.coordinate, selectedAccommodation?.coordinate].compactMap { $0 },
                animated: true
            )
        }
    }

    func refreshLocalTransfersInBackground() {
        transferTask?.cancel()
        transferTask = Task { [weak self] in
            await self?.refreshLocalTransfers()
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
            let coordinates = [
                selectedTransport?.arrivalAccessPoint?.coordinate,
                selectedReturnTransport?.arrivalAccessPoint?.coordinate,
                selectedAccommodation?.coordinate
            ]
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

    private func clearLocalTransfers() {
        transferTask?.cancel()
        outboundTransferOptions = []
        selectedOutboundTransferID = nil
        returnTransferOptions = []
        selectedReturnTransferID = nil
        transferRoutesByOptionID = [:]
        isTransferLoading = false
        transferStatusMessage = nil
    }

    private func refreshLocalTransfers() async {
        guard !draft.logistics.skipTransport,
              let accommodation = selectedAccommodation else {
            clearLocalTransfers()
            return
        }

        let previousOutboundMode = selectedOutboundTransfer?.mode
        let previousReturnMode = selectedReturnTransfer?.mode
        isTransferLoading = true
        transferStatusMessage = "正在向地图询问接驳路线"
        defer { isTransferLoading = false }

        var outboundResult = LocalTransferResult(options: [], routesByOptionID: [:], failedModes: [])
        if let accessPoint = selectedTransport?.arrivalAccessPoint {
            outboundResult = await localTransferService.buildOptions(
                direction: .outbound,
                accessPoint: accessPoint,
                accommodation: accommodation,
                travelers: draft.logistics.travelers,
                referenceDate: selectedTransport?.arrivalTime
            )
        }
        guard !Task.isCancelled else { return }

        var returnResult = LocalTransferResult(options: [], routesByOptionID: [:], failedModes: [])
        if let accessPoint = selectedReturnTransport?.arrivalAccessPoint {
            let leaveHotelAt = selectedReturnTransport?.departureTime?.addingTimeInterval(-90 * 60)
            returnResult = await localTransferService.buildOptions(
                direction: .returnTrip,
                accessPoint: accessPoint,
                accommodation: accommodation,
                travelers: draft.logistics.travelers,
                referenceDate: leaveHotelAt
            )
        }
        guard !Task.isCancelled else { return }

        let newRoutes = outboundResult.routesByOptionID.merging(returnResult.routesByOptionID) { _, latest in latest }
        if UIAccessibility.isReduceMotionEnabled {
            outboundTransferOptions = outboundResult.options
            returnTransferOptions = returnResult.options
            transferRoutesByOptionID = newRoutes
        } else {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                outboundTransferOptions = outboundResult.options
                returnTransferOptions = returnResult.options
                transferRoutesByOptionID = newRoutes
            }
        }
        selectedOutboundTransferID = outboundTransferOptions.first(where: { $0.mode == previousOutboundMode })?.id
            ?? outboundTransferOptions.first(where: \.isRecommended)?.id
            ?? outboundTransferOptions.first?.id
        selectedReturnTransferID = returnTransferOptions.first(where: { $0.mode == previousReturnMode })?.id
            ?? returnTransferOptions.first(where: \.isRecommended)?.id
            ?? returnTransferOptions.first?.id

        let failedCount = outboundResult.failedModes.count + returnResult.failedModes.count
        let hasTransitEstimate = (outboundTransferOptions + returnTransferOptions)
            .contains { $0.mode == .publicTransit && $0.routeKind == .distanceEstimate }
        if outboundTransferOptions.isEmpty && returnTransferOptions.isEmpty {
            transferStatusMessage = "Apple Maps 暂时没有带回可用接驳路线"
        } else if hasTransitEstimate {
            transferStatusMessage = "公交路线暂未返回，已按距离估算；出发前请在地图复核"
        } else if failedCount > 0 {
            transferStatusMessage = "部分接驳方式暂未返回，已保留可用路线"
        } else {
            transferStatusMessage = nil
        }
    }

    private func rebuildTransportOptions() {
        guard let destination else { return }
        guard !draft.logistics.skipTransport else {
            transportOptions = []
            selectedTransportID = nil
            returnTransportOptions = []
            selectedReturnTransportID = nil
            clearLocalTransfers()
            return
        }
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

    private func refreshTransportQuotes() async throws -> PricingEnrichmentResult<[TransportOption]> {
        let previousOutboundTitle = selectedTransport?.title
        let previousReturnTitle = selectedReturnTransport?.title
        let currentOptions = transportOptions + returnTransportOptions
        var result = PricingEnrichmentResult(
            value: currentOptions,
            receivedCount: 0,
            capturedAt: Date.now,
            isCached: false,
            issues: []
        )
        if pricingBackendClient.isConfigured {
            do {
                result = try await pricingBackendClient.enrichTransportOptions(
                    currentOptions,
                    origin: draft.logistics.origin,
                    destination: draft.destination,
                    logistics: draft.logistics,
                    accessPoints: accessPoints,
                    accommodation: selectedAccommodation
                )
            } catch {
                result.issues.insert(
                    PricingProviderIssue(
                        provider: "报价节点",
                        status: "failed",
                        detail: "多渠道节点暂未抵达，已改由应用内实时来源继续：\(Self.pricingFailureText(error))"
                    ),
                    at: 0
                )
            }
        }

        do {
            let railwayResult = try await railway12306DirectClient.enrichTransportOptions(
                result.value,
                origin: draft.logistics.origin,
                destination: draft.destination,
                logistics: draft.logistics,
                accessPoints: accessPoints,
                accommodation: selectedAccommodation
            )
            result.value = railwayResult.value
            result.receivedCount += railwayResult.receivedCount
            result.capturedAt = max(result.capturedAt, railwayResult.capturedAt)
            result.isCached = result.isCached && railwayResult.isCached
            result.issues.append(contentsOf: railwayResult.issues)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.issues.append(
                PricingProviderIssue(
                    provider: "12306",
                    status: "failed",
                    detail: Self.pricingFailureText(error)
                )
            )
        }

        do {
            let fliggyResult = try await fliggyFlightDirectClient.enrichTransportOptions(
                result.value,
                origin: draft.logistics.origin,
                destination: draft.destination,
                logistics: draft.logistics,
                accessPoints: accessPoints,
                accommodation: selectedAccommodation
            )
            result.value = fliggyResult.value
            result.receivedCount += fliggyResult.receivedCount
            result.capturedAt = max(result.capturedAt, fliggyResult.capturedAt)
            result.isCached = result.isCached && fliggyResult.isCached
            result.issues.append(contentsOf: fliggyResult.issues)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.issues.append(
                PricingProviderIssue(
                    provider: "fliggy",
                    status: "failed",
                    detail: Self.pricingFailureText(error)
                )
            )
        }

        do {
            let qunarResult = try await qunarFlightDirectClient.enrichTransportOptions(
                result.value,
                origin: draft.logistics.origin,
                destination: draft.destination,
                logistics: draft.logistics,
                accessPoints: accessPoints,
                accommodation: selectedAccommodation
            )
            result.value = qunarResult.value
            result.receivedCount += qunarResult.receivedCount
            result.capturedAt = max(result.capturedAt, qunarResult.capturedAt)
            result.isCached = result.isCached && qunarResult.isCached
            result.issues.append(contentsOf: qunarResult.issues)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.issues.append(
                PricingProviderIssue(
                    provider: "qunar",
                    status: "failed",
                    detail: Self.pricingFailureText(error)
                )
            )
        }
        guard !Task.isCancelled else { throw CancellationError() }
        let outboundOptions = result.value.filter { $0.journeyDirection == .outbound }
        let inboundOptions = result.value.filter { $0.journeyDirection == .returnTrip }
        if UIAccessibility.isReduceMotionEnabled {
            transportOptions = outboundOptions
            returnTransportOptions = inboundOptions
        } else {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) {
                transportOptions = outboundOptions
                returnTransportOptions = inboundOptions
            }
        }
        if !transportOptions.contains(where: { $0.id == selectedTransportID }) {
            selectedTransportID = transportOptions.first(where: { $0.title == previousOutboundTitle })?.id
                ?? transportOptions.first(where: \.isRecommended)?.id
                ?? transportOptions.first?.id
        }
        if !returnTransportOptions.contains(where: { $0.id == selectedReturnTransportID }) {
            selectedReturnTransportID = returnTransportOptions.first(where: { $0.title == previousReturnTitle })?.id
                ?? returnTransportOptions.first(where: \.isRecommended)?.id
                ?? returnTransportOptions.first?.id
        }
        return result
    }

    private static func pricingFailureText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func firstUniqueMessages(in messages: [String], limit: Int = 2) -> [String] {
        var seen: Set<String> = []
        return messages.filter { seen.insert($0).inserted }.prefix(limit).map(\.self)
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
        exportTask?.cancel()
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
        travelRequestText = ""
        adjustmentText = ""
        planMapFocus = .itinerary
        accommodations = []
        selectedAccommodationID = nil
        accessPoints = []
        transportOptions = []
        selectedTransportID = nil
        returnTransportOptions = []
        selectedReturnTransportID = nil
        clearLocalTransfers()
        focusedTransportDirection = .outbound
        isLogisticsLoading = false
        logisticsStatusMessage = nil
        quoteRefreshState = .idle
        isExportingPlan = false
        exportStatusMessage = nil
        sharePayload = nil
        paceStatusMessage = nil
        originResolution = nil
        activeSavedTripID = nil
        itineraryEditorPresented = false
        conditionsEditorPresented = false
        itineraryNeedsLogisticsRefresh = false
        clearItineraryHistory()
        cameraPosition = .region(Self.initialRegion)
    }

    func cycleMapAppearance() {
        let all = MapAppearance.allCases
        guard let index = all.firstIndex(of: mapAppearance) else { return }
        mapAppearance = all[(index + 1) % all.count]
        mapActionFeedbackTrigger += 1
    }

    func focusUserLocation() {
        let fallback: MapCameraPosition = if let destination {
            .region(destination.region)
        } else {
            .region(Self.initialRegion)
        }
        setCamera(.userLocation(followsHeading: false, fallback: fallback), animated: true)
        noticeMessage = "正在回到你的位置；若尚未允许定位，地图会停在当前旅程。"
        mapActionFeedbackTrigger += 1
    }

    func orientMapNorth() {
        if phase == .ready, !currentStops.isEmpty {
            fitCurrentDay(animated: true)
        } else if let destination {
            setCamera(.region(destination.region), animated: true)
        } else {
            setCamera(.region(Self.initialRegion), animated: true)
        }
        noticeMessage = "地图已回到北向。"
        mapActionFeedbackTrigger += 1
    }

    private func itineraryDidChange(dayIndex: Int, message: String, refreshRoute: Bool) {
        itineraryDidChange(dayIndices: [dayIndex], message: message, refreshRoute: refreshRoute)
    }

    private func itineraryDidChange(
        dayIndices: Set<Int>,
        message: String,
        refreshRoute: Bool
    ) {
        for dayIndex in dayIndices {
            routesByDay[dayIndex] = nil
            failedSegmentsByDay[dayIndex] = nil
        }
        visibleLegCount = 0
        noticeMessage = message
        paceStatusMessage = nil
        quoteRefreshState = .stale("景点分布变了，住处距离与接驳方式需要重新丈量。")
        itineraryNeedsLogisticsRefresh = true
        fitCurrentDay(animated: true)

        guard refreshRoute, dayIndices.contains(selectedDayIndex) else { return }
        routeTask?.cancel()
        revealTask?.cancel()
        routeTask = Task { [weak self] in
            await self?.loadRoutesForSelectedDay(reveal: true)
        }
    }

    private func currentItinerarySnapshot() -> ItineraryEditSnapshot {
        ItineraryEditSnapshot(
            days: itineraryDays,
            selectedDayIndex: selectedDayIndex,
            selectedPlaceID: selectedPlaceID
        )
    }

    private func rememberItineraryForUndo(_ snapshot: ItineraryEditSnapshot? = nil) {
        let snapshot = snapshot ?? currentItinerarySnapshot()
        guard itineraryUndoStack.last != snapshot else { return }
        itineraryUndoStack.append(snapshot)
        if itineraryUndoStack.count > 30 {
            itineraryUndoStack.removeFirst(itineraryUndoStack.count - 30)
        }
        itineraryRedoStack.removeAll()
        syncItineraryHistoryAvailability()
    }

    private func restoreItinerarySnapshot(
        _ snapshot: ItineraryEditSnapshot,
        message: String,
        refreshRoute: Bool
    ) {
        let affectedDays = Set(itineraryDays.map(\.index)).union(snapshot.days.map(\.index))
        itineraryDays = snapshot.days
        selectedDayIndex = itineraryDays.contains(where: { $0.index == snapshot.selectedDayIndex })
            ? snapshot.selectedDayIndex
            : itineraryDays.first?.index ?? 0
        selectedPlaceID = itineraryDays
            .first(where: { $0.index == selectedDayIndex })?
            .stops
            .contains(where: { $0.id == snapshot.selectedPlaceID }) == true
            ? snapshot.selectedPlaceID
            : nil
        itineraryDidChange(
            dayIndices: affectedDays,
            message: message,
            refreshRoute: refreshRoute
        )
    }

    private func clearItineraryHistory() {
        itineraryUndoStack.removeAll()
        itineraryRedoStack.removeAll()
        syncItineraryHistoryAvailability()
    }

    private func syncItineraryHistoryAvailability() {
        canUndoItineraryChange = !itineraryUndoStack.isEmpty
        canRedoItineraryChange = !itineraryRedoStack.isEmpty
    }

    private func containsEquivalentPlace(_ place: TravelPlace, in dayIndex: Int? = nil) -> Bool {
        let existingPlaces = itineraryDays
            .filter { dayIndex == nil || $0.index == dayIndex }
            .flatMap(\.stops)
        return routePlanner.deduplicatedPlaces(existingPlaces + [place]).count == existingPlaces.count
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
                withAnimation(.spring(response: 0.46, dampingFraction: 0.80)) {
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

    private var routeTravelMinutesByDay: [Int: Int] {
        routesByDay.mapValues { legs in
            max(Int((legs.reduce(0) { $0 + $1.route.expectedTravelTime } / 60).rounded()), 0)
        }
    }

    private var tourismConstraintsByDay: [Int: TourismDayConstraints] {
        Dictionary(uniqueKeysWithValues: itineraryDays.compactMap { day in
            let constraints = tourismConstraints(for: day)
            guard constraints != .none else { return nil }
            return (day.index, constraints)
        })
    }

    private func tourismConstraints(for day: ItineraryDay) -> TourismDayConstraints {
        guard !itineraryDays.isEmpty else { return .none }
        var constraints = TourismDayConstraints.none

        if day.index == itineraryDays.first?.index,
           let arrivalTime = selectedTransport?.arrivalTime {
            let transferMinutes = selectedOutboundTransfer?.durationMinutes
                ?? (draft.logistics.skipAccommodation ? 30 : 45)
            let exitAndSettleMinutes: Int = switch selectedTransport?.mode {
            case .some(.flight): 45
            case .some(.train): 25
            case .some(.coach): 20
            case .some(.driving): 10
            case .none: 25
            }
            let rawStart = Self.minuteOfDay(arrivalTime) + transferMinutes + exitAndSettleMinutes
            constraints.earliestStartMinute = min(rawStart, 23 * 60 + 55)
            constraints.startNote = rawStart >= 24 * 60
                ? "抵达、出站与接驳预计跨过午夜，当天不宜再排主要游览"
                : "按抵达时刻，加上约\(transferMinutes)分钟接驳和\(exitAndSettleMinutes)分钟出站安顿后开始"
        }

        if day.index == itineraryDays.last?.index,
           let departureTime = selectedReturnTransport?.departureTime {
            let transferMinutes = selectedReturnTransfer?.durationMinutes ?? 45
            let checkInBufferMinutes: Int = switch selectedReturnTransport?.mode {
            case .some(.flight): 120
            case .some(.train): 60
            case .some(.coach): 60
            case .some(.driving): 15
            case .none: 60
            }
            let leaveBy = Self.minuteOfDay(departureTime) - transferMinutes - checkInBufferMinutes
            constraints.latestEndMinute = max(leaveBy, 0)
            constraints.endNote = "按约\(transferMinutes)分钟接驳，并为\(selectedReturnTransport?.mode.shortTitle ?? "返程")预留\(checkInBufferMinutes)分钟提前到达"
        }

        return constraints
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return max((components.hour ?? 0) * 60 + (components.minute ?? 0), 0)
    }

    private func showFailure(_ error: Error, recovery: RecoveryAction) {
        recoveryAction = recovery
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .failure
    }

    private static func looksLikeDestination(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 24, !text.contains(where: { $0.isNewline }) else { return false }
        let blockedWords = ["预算", "酒店", "住宿", "轻松", "紧凑", "公交", "步行", "自驾", "几天", "价格"]
        return !blockedWords.contains(where: text.contains)
            && text.rangeOfCharacter(from: .punctuationCharacters) == nil
    }

    private static let assistantDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.35, longitude: 108.94),
        span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 31)
    )
}
