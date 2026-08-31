package cn.anytravel.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val LocalReduceMotion = staticCompositionLocalOf { false }

private val LightColors = lightColorScheme(
    primary = HorizonTeal,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD1EEE9),
    onPrimaryContainer = ForestInk,
    secondary = TravelOrange,
    onSecondary = Color.White,
    background = Mist,
    onBackground = ForestInk,
    surface = Color(0xFFF8FBFA),
    onSurface = ForestInk,
    surfaceVariant = Color(0xFFE4EEEB),
    onSurfaceVariant = TideGray,
    outline = Color(0xFF7E9691),
    error = Color(0xFFB83A38)
)

private val DarkColors = darkColorScheme(
    primary = HorizonTealDark,
    onPrimary = Color(0xFF063D38),
    primaryContainer = Color(0xFF185B55),
    onPrimaryContainer = Color(0xFFD5F2ED),
    secondary = Color(0xFFFF8767),
    onSecondary = Color(0xFF4E1507),
    background = Color(0xFF0C1513),
    onBackground = NightInk,
    surface = NightSurface,
    onSurface = NightInk,
    surfaceVariant = Color(0xFF243431),
    onSurfaceVariant = NightSecondary,
    outline = Color(0xFF78918B),
    error = Color(0xFFFF8A86)
)

private val AnyTravelTypography = Typography(
    displaySmall = TextStyle(fontSize = 34.sp, lineHeight = 42.sp, fontWeight = FontWeight.SemiBold),
    headlineMedium = TextStyle(fontSize = 27.sp, lineHeight = 34.sp, fontWeight = FontWeight.SemiBold),
    headlineSmall = TextStyle(fontSize = 22.sp, lineHeight = 29.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 17.sp, lineHeight = 23.sp, fontWeight = FontWeight.Medium),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 12.sp, lineHeight = 17.sp, fontWeight = FontWeight.Medium)
)

@Composable
fun AnyTravelTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    reduceMotion: Boolean = false,
    content: @Composable () -> Unit
) {
    androidx.compose.runtime.CompositionLocalProvider(LocalReduceMotion provides reduceMotion) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkColors else LightColors,
            typography = AnyTravelTypography,
            content = content
        )
    }
}
