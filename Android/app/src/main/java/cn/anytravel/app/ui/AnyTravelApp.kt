package cn.anytravel.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cn.anytravel.app.ui.screens.OnboardingScreen
import cn.anytravel.app.ui.screens.PlannerScreen

@Composable
fun AnyTravelApp(viewModel: PlannerViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    if (!state.onboardingComplete) {
        OnboardingScreen(
            initialOrigin = state.draft.origin,
            initialBudget = state.draft.budgetPerPerson,
            initialTravelers = state.draft.travelers,
            onComplete = viewModel::completeOnboarding,
            onSkip = viewModel::skipOnboarding
        )
    } else {
        PlannerScreen(state = state, viewModel = viewModel)
    }
}
