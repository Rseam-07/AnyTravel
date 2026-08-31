package cn.anytravel.app

import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import cn.anytravel.app.data.AppRepository
import cn.anytravel.app.domain.createSystemGeocoder
import cn.anytravel.app.ui.AnyTravelApp
import cn.anytravel.app.ui.PlannerViewModel
import cn.anytravel.app.ui.PlannerViewModelFactory
import cn.anytravel.app.ui.theme.AnyTravelTheme
import org.maplibre.android.MapLibre

class MainActivity : ComponentActivity() {
    private val repository by lazy { AppRepository(applicationContext) }
    private val viewModel: PlannerViewModel by viewModels {
        PlannerViewModelFactory(repository, createSystemGeocoder(applicationContext))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra(EXTRA_SKIP_ONBOARDING, false)) repository.skipOnboarding()
        MapLibre.getInstance(this)
        enableEdgeToEdge()
        setContent {
            AnyTravelTheme(reduceMotion = animatorScaleIsZero()) {
                AnyTravelApp(viewModel = viewModel)
            }
        }
    }

    private fun animatorScaleIsZero(): Boolean = runCatching {
        Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }.getOrDefault(false)

    companion object {
        const val EXTRA_SKIP_ONBOARDING = "skip_onboarding"
    }
}
