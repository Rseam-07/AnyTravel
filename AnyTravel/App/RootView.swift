import SwiftUI

enum PlannerPanelDetent: Int, CaseIterable {
    case compact
    case medium
    case expanded

    var accessibilityTitle: String {
        switch self {
        case .compact: "仅显示输入框"
        case .medium: "显示主要内容"
        case .expanded: "几乎全屏显示"
        }
    }
}

struct PlannerPanelMetrics: Equatable {
    let compact: CGFloat
    let medium: CGFloat
    let expanded: CGFloat

    func height(for detent: PlannerPanelDetent) -> CGFloat {
        switch detent {
        case .compact: compact
        case .medium: medium
        case .expanded: expanded
        }
    }

    func closestDetent(to proposedHeight: CGFloat) -> PlannerPanelDetent {
        PlannerPanelDetent.allCases.min {
            abs(height(for: $0) - proposedHeight) < abs(height(for: $1) - proposedHeight)
        } ?? .medium
    }
}

enum PlannerPanelLayout {
    static func metrics(containerHeight: CGFloat, safeAreaTop: CGFloat) -> PlannerPanelMetrics {
        let compact: CGFloat = 126
        let expanded = max(compact, containerHeight - max(safeAreaTop, 12) - 10)
        let idealMedium = min(max(containerHeight * 0.61, 430), 570)
        let medium = min(max(idealMedium, compact + 180), max(expanded - 116, compact))
        return PlannerPanelMetrics(compact: compact, medium: medium, expanded: expanded)
    }

    static func preferredHeight(
        phase: PlannerPhase,
        focus: PlanMapFocus,
        stopCount: Int,
        isLoadingLogistics: Bool,
        hasSelectedPlace: Bool = false,
        hasPacingMessage: Bool = false,
        accommodationCount: Int = 0,
        transportCount: Int = 0,
        metrics: PlannerPanelMetrics
    ) -> CGFloat {
        let proposed: CGFloat = switch phase {
        case .destination: 405
        case .preferences: min(max(metrics.medium + 35, 540), 610)
        case .discovering: 238
        case .failure: 318
        case .ready:
            switch focus {
            case .itinerary:
                min(
                    470
                        + CGFloat(min(stopCount, 4)) * 17
                        + (hasSelectedPlace ? 46 : 0)
                        + (hasPacingMessage ? 32 : 0),
                    608
                )
            case .accommodation:
                isLoadingLogistics ? 440 : min(520 + CGFloat(min(accommodationCount, 2)) * 24, 568)
            case .transport:
                isLoadingLogistics ? 440 : min(530 + CGFloat(min(transportCount, 2)) * 22, 574)
            case .budget: 535
            }
        }
        return min(max(proposed, metrics.compact), metrics.expanded)
    }
}

private enum PlannerRootSheet: String, Identifiable {
    case library
    case settings

    var id: String { rawValue }
}

struct RootView: View {
    @State private var model = PlannerViewModel()
    @State private var providerSessionStore = ProviderSessionStore()
    @State private var onboardingDismissedForRun = false
    @State private var panelDetent: PlannerPanelDetent = .medium
    @State private var rootSheet: PlannerRootSheet?
    @AppStorage("AnyTravelCompletedOnboardingV1") private var completedOnboarding = false
    @Namespace private var mapScope

    var body: some View {
        @Bindable var bindableModel = model

        ZStack(alignment: .bottom) {
            PlannerMapView(model: model, mapScope: mapScope)
            PlannerPanelHost(model: model, detent: $panelDetent)
        }
        .overlay(alignment: .top) {
            PlannerChrome(
                model: model,
                panelDetent: panelDetent,
                openSettings: { rootSheet = .settings },
                openLibrary: { rootSheet = .library }
            )
                .zIndex(10)
        }
        .sheet(item: $rootSheet) { destination in
            Group {
                switch destination {
                case .library:
                    SavedTripsView(model: model)
                case .settings:
                    SettingsView(model: model, sessionStore: providerSessionStore)
                }
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableModel.itineraryEditorPresented) {
            ItineraryEditorView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableModel.conditionsEditorPresented) {
            TripConditionsView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableModel.attractionPickerPresented) {
            AttractionSelectionView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $bindableModel.activeProviderPage) { destination in
            ProviderBrowserView(destination: destination)
        }
        .sheet(item: $bindableModel.sharePayload) { payload in
            ActivityShareView(payload: payload)
                .ignoresSafeArea()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    !onboardingDismissedForRun
                        && (!completedOnboarding || ProcessInfo.processInfo.arguments.contains("--force-onboarding"))
                        && !ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
                        && !ProcessInfo.processInfo.arguments.contains("--ui-test-ready")
                },
                set: { presented in
                    if !presented {
                        completedOnboarding = true
                        onboardingDismissedForRun = true
                    }
                }
            )
        ) {
            OnboardingView(model: model, sessionStore: providerSessionStore) {
                model.persistPlanningDefaults()
                completedOnboarding = true
                onboardingDismissedForRun = true
            }
            .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: model.saveFeedbackTrigger)
        .sensoryFeedback(.success, trigger: model.planReadyFeedbackTrigger)
        .sensoryFeedback(.success, trigger: model.exportFeedbackTrigger)
        .sensoryFeedback(.success, trigger: model.paceFeedbackTrigger)
        .sensoryFeedback(.success, trigger: model.assistantFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: model.mapActionFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: panelDetent)
        .sensoryFeedback(.selection, trigger: model.planMapFocus)
        .sensoryFeedback(.selection, trigger: model.selectedDayIndex)
        .onChange(of: model.settingsPresented) { _, presented in
            guard presented else { return }
            model.settingsPresented = false
            rootSheet = .settings
        }
        .onChange(of: model.libraryPresented) { _, presented in
            guard presented else { return }
            model.libraryPresented = false
            rootSheet = .library
        }
        .task {
            await providerSessionStore.reconcileSavedSessions()
            await model.bootstrapIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-settings") {
                try? await Task.sleep(for: .milliseconds(250))
                model.assistantSettings.mode = .managed
                rootSheet = .settings
            }
            guard ProcessInfo.processInfo.arguments.contains("--motion-showcase-ready") else { return }
            try? await Task.sleep(for: .milliseconds(1_500))
            for focus in [PlanMapFocus.accommodation, .transport, .budget, .itinerary] {
                guard !Task.isCancelled else { return }
                model.setPlanMapFocus(focus)
                try? await Task.sleep(for: .milliseconds(1_450))
            }
            #endif
        }
    }
}

private struct PlannerPanelHost: View {
    @Bindable var model: PlannerViewModel
    @Binding var detent: PlannerPanelDetent
    @State private var manualDetent: PlannerPanelDetent?
    @GestureState private var dragTranslation: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let metrics = PlannerPanelLayout.metrics(
                containerHeight: geometry.size.height,
                safeAreaTop: geometry.safeAreaInsets.top
            )
            let automaticHeight = preferredHeight(metrics: metrics)
            let settledHeight = manualDetent.map { metrics.height(for: $0) } ?? automaticHeight
            let panelHeight = clamped(settledHeight - (dragTranslation ?? 0), metrics: metrics)
            let displayDetent = manualDetent ?? metrics.closestDetent(to: automaticHeight)

            // Keep the gesture surface outside the changing panel content. The
            // transient translation resets even when the system cancels a drag.
            ZStack(alignment: .top) {
                PlannerPanel(model: model, panelDetent: displayDetent)
                panelHandle(metrics: metrics, displayDetent: displayDetent, settledHeight: settledHeight)
            }
                .frame(maxWidth: 560)
                .frame(height: panelHeight, alignment: .top)
                .clipped()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(
                    dragTranslation == nil ? AnyTravelMotion.settle(reduceMotion: reduceMotion) : nil,
                    value: panelHeight
                )
                .onAppear {
                    detent = displayDetent
                }
                .onChange(of: displayDetent) { _, nextDetent in detent = nextDetent }
                .onChange(of: autoFitToken) { _, _ in
                    withAnimation(AnyTravelMotion.settle(reduceMotion: reduceMotion)) {
                        manualDetent = nil
                    }
                }
        }
    }

    private func panelHandle(
        metrics: PlannerPanelMetrics,
        displayDetent: PlannerPanelDetent,
        settledHeight: CGFloat
    ) -> some View {
        Capsule()
            .fill(.secondary.opacity(0.30))
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
            .padding(.top, 10)
            .contentShape(Rectangle())
            .gesture(panelDragGesture(metrics: metrics, settledHeight: settledHeight))
            .onTapGesture {
                movePanel(up: displayDetent != .expanded)
            }
            .accessibilityElement()
            .accessibilityLabel("调整地图面板高度")
            .accessibilityValue(displayDetent.accessibilityTitle)
            .accessibilityHint("上下拖动可自由调整；轻点切换高度")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("planner-panel-drag-handle")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: movePanel(up: true)
                case .decrement: movePanel(up: false)
                @unknown default: break
                }
            }
    }

    private func panelDragGesture(metrics: PlannerPanelMetrics, settledHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($dragTranslation) { value, translation, transaction in
                transaction.animation = nil
                translation = value.translation.height
            }
            .onEnded { value in
                let predictedHeight = clamped(
                    settledHeight - value.predictedEndTranslation.height,
                    metrics: metrics
                )
                settle(at: metrics.closestDetent(to: predictedHeight))
            }
    }

    private func movePanel(up: Bool) {
        let currentIndex = PlannerPanelDetent.allCases.firstIndex(of: detent) ?? 1
        let nextIndex = min(max(currentIndex + (up ? 1 : -1), 0), PlannerPanelDetent.allCases.count - 1)
        settle(at: PlannerPanelDetent.allCases[nextIndex])
    }

    private func settle(at nextDetent: PlannerPanelDetent) {
        withAnimation(AnyTravelMotion.settle(reduceMotion: reduceMotion)) {
            manualDetent = nextDetent
            detent = nextDetent
        }
    }

    private var autoFitToken: PlannerPanelAutoFitToken {
        PlannerPanelAutoFitToken(
            phase: model.phase,
            focus: model.planMapFocus,
            destination: model.draft.destination,
            dayCount: model.draft.dayCount,
            budgetPerPerson: model.draft.budgetPerPerson,
            pace: model.draft.pace,
            travelMode: model.draft.travelMode,
            origin: model.draft.logistics.origin,
            travelers: model.draft.logistics.travelers,
            startDate: model.draft.logistics.startDate,
            endDate: model.draft.logistics.endDate,
            preferredLongDistanceMode: model.draft.logistics.preferredLongDistanceMode,
            skipAccommodation: model.draft.logistics.skipAccommodation,
            skipTransport: model.draft.logistics.skipTransport,
            interestCount: model.draft.interests.count,
            selectedDayIndex: model.selectedDayIndex,
            selectedPlaceID: model.selectedPlaceID,
            selectedAccommodationID: model.selectedAccommodationID,
            selectedTransportID: model.selectedTransportID,
            selectedReturnTransportID: model.selectedReturnTransportID,
            accommodationSort: model.accommodationSort,
            accommodationFilterCount: model.activeAccommodationFilterCount,
            accommodationCount: model.filteredAccommodations.count,
            transportCount: model.focusedTransportDirection == .outbound
                ? model.transportOptions.count
                : model.returnTransportOptions.count,
            isLogisticsLoading: model.isLogisticsLoading,
            quoteRefreshState: model.quoteRefreshState,
            paceStatusMessage: model.paceStatusMessage,
            noticeMessage: model.noticeMessage,
            itineraryCount: model.itineraryDays.reduce(0) { $0 + $1.stops.count }
        )
    }

    private func preferredHeight(metrics: PlannerPanelMetrics) -> CGFloat {
        PlannerPanelLayout.preferredHeight(
            phase: model.phase,
            focus: model.planMapFocus,
            stopCount: model.currentStops.count,
            isLoadingLogistics: model.isLogisticsLoading,
            hasSelectedPlace: model.selectedPlace != nil,
            hasPacingMessage: model.paceStatusMessage != nil || model.planPacingAssessment.needsAttention,
            accommodationCount: model.filteredAccommodations.count,
            transportCount: model.focusedTransportDirection == .outbound
                ? model.transportOptions.count
                : model.returnTransportOptions.count,
            metrics: metrics
        )
    }

    private func clamped(_ height: CGFloat, metrics: PlannerPanelMetrics) -> CGFloat {
        min(max(height, metrics.compact), metrics.expanded)
    }
}

private struct PlannerPanelAutoFitToken: Equatable {
    var phase: PlannerPhase
    var focus: PlanMapFocus
    var destination: String
    var dayCount: Int
    var budgetPerPerson: Int
    var pace: TripPace
    var travelMode: TravelMode
    var origin: String
    var travelers: Int
    var startDate: Date?
    var endDate: Date?
    var preferredLongDistanceMode: LongDistanceMode?
    var skipAccommodation: Bool
    var skipTransport: Bool
    var interestCount: Int
    var selectedDayIndex: Int
    var selectedPlaceID: UUID?
    var selectedAccommodationID: UUID?
    var selectedTransportID: UUID?
    var selectedReturnTransportID: UUID?
    var accommodationSort: AccommodationSort
    var accommodationFilterCount: Int
    var accommodationCount: Int
    var transportCount: Int
    var isLogisticsLoading: Bool
    var quoteRefreshState: QuoteRefreshState
    var paceStatusMessage: String?
    var noticeMessage: String?
    var itineraryCount: Int
}

#Preview {
    RootView()
}
