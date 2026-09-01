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
    @State private var dragOriginHeight: CGFloat?
    @State private var liveHeight: CGFloat?
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let metrics = PlannerPanelLayout.metrics(
                containerHeight: geometry.size.height,
                safeAreaTop: geometry.safeAreaInsets.top
            )
            let panelHeight = clamped(liveHeight ?? metrics.height(for: detent), metrics: metrics)
            let displayDetent = metrics.closestDetent(to: panelHeight)

            PlannerPanel(model: model, panelDetent: displayDetent)
                .frame(maxWidth: 560)
                .frame(height: panelHeight, alignment: .top)
                .clipped()
                .overlay(alignment: .top) {
                    panelHandle(metrics: metrics, displayDetent: displayDetent)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(
                    liveHeight == nil ? AnyTravelMotion.settle(reduceMotion: reduceMotion) : nil,
                    value: panelHeight
                )
                .onChange(of: isDragging) { wasDragging, isDragging in
                    guard wasDragging, !isDragging else { return }
                    liveHeight = nil
                    dragOriginHeight = nil
                }
        }
    }

    private func panelHandle(
        metrics: PlannerPanelMetrics,
        displayDetent: PlannerPanelDetent
    ) -> some View {
        Capsule()
            .fill(.secondary.opacity(0.30))
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
            .padding(.top, 10)
            .contentShape(Rectangle())
            .gesture(panelDragGesture(metrics: metrics))
            .onTapGesture {
                movePanel(up: displayDetent != .expanded, metrics: metrics)
            }
            .accessibilityElement()
            .accessibilityLabel("调整地图面板高度")
            .accessibilityValue(displayDetent.accessibilityTitle)
            .accessibilityHint("上下拖动可自由调整；轻点切换高度")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("planner-panel-drag-handle")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: movePanel(up: true, metrics: metrics)
                case .decrement: movePanel(up: false, metrics: metrics)
                @unknown default: break
                }
            }
    }

    private func panelDragGesture(metrics: PlannerPanelMetrics) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($isDragging) { _, isDragging, _ in
                isDragging = true
            }
            .onChanged { value in
                let origin = dragOriginHeight ?? metrics.height(for: detent)
                if dragOriginHeight == nil { dragOriginHeight = origin }
                let proposedHeight = clamped(origin - value.translation.height, metrics: metrics)
                liveHeight = proposedHeight
                detent = metrics.closestDetent(to: proposedHeight)
            }
            .onEnded { value in
                let origin = dragOriginHeight ?? metrics.height(for: detent)
                let predictedHeight = clamped(
                    origin - value.predictedEndTranslation.height,
                    metrics: metrics
                )
                settle(at: metrics.closestDetent(to: predictedHeight))
            }
    }

    private func movePanel(up: Bool, metrics: PlannerPanelMetrics) {
        let currentIndex = PlannerPanelDetent.allCases.firstIndex(of: detent) ?? 1
        let nextIndex = min(max(currentIndex + (up ? 1 : -1), 0), PlannerPanelDetent.allCases.count - 1)
        settle(at: PlannerPanelDetent.allCases[nextIndex])
    }

    private func settle(at nextDetent: PlannerPanelDetent) {
        withAnimation(AnyTravelMotion.settle(reduceMotion: reduceMotion)) {
            detent = nextDetent
            liveHeight = nil
            dragOriginHeight = nil
        }
    }

    private func clamped(_ height: CGFloat, metrics: PlannerPanelMetrics) -> CGFloat {
        min(max(height, metrics.compact), metrics.expanded)
    }
}

#Preview {
    RootView()
}
