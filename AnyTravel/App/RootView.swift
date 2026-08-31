import SwiftUI

struct RootView: View {
    @State private var model = PlannerViewModel()
    @State private var providerSessionStore = ProviderSessionStore()
    @State private var onboardingDismissedForRun = false
    @AppStorage("AnyTravelCompletedOnboardingV1") private var completedOnboarding = false
    @Namespace private var mapScope

    var body: some View {
        @Bindable var bindableModel = model

        ZStack {
            PlannerMapView(model: model, mapScope: mapScope)
            PlannerChrome(model: model, mapScope: mapScope)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlannerPanel(model: model)
                .frame(maxWidth: 560)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $bindableModel.libraryPresented) {
            SavedTripsView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableModel.settingsPresented) {
            SettingsView(model: model, sessionStore: providerSessionStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $bindableModel.activeProviderPage) { destination in
            ProviderBrowserView(destination: destination)
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
        .task {
            await model.bootstrapIfNeeded()
        }
    }
}

#Preview {
    RootView()
}
