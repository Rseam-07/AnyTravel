import SwiftUI

struct RootView: View {
    @State private var model = PlannerViewModel()
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
        .sensoryFeedback(.success, trigger: model.saveFeedbackTrigger)
        .task {
            await model.bootstrapIfNeeded()
        }
    }
}

#Preview {
    RootView()
}
