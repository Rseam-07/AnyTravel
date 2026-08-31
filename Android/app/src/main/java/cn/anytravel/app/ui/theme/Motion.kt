package cn.anytravel.app.ui.theme

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable

object AnyTravelMotion {
    @Composable
    fun <T> snappy() = if (LocalReduceMotion.current) {
        tween<T>(durationMillis = 120)
    } else {
        spring<T>(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
    }

    @Composable
    fun <T> settle() = if (LocalReduceMotion.current) {
        tween<T>(durationMillis = 160)
    } else {
        spring<T>(dampingRatio = 0.84f, stiffness = Spring.StiffnessLow)
    }

    @Composable
    fun routeDuration(): Int = if (LocalReduceMotion.current) 0 else 850
}
