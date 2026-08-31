package cn.anytravel.app.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.AltRoute
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bed
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Map
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cn.anytravel.app.ui.theme.HorizonTeal
import cn.anytravel.app.ui.theme.LocalReduceMotion
import cn.anytravel.app.ui.theme.TravelOrange
import kotlinx.coroutines.launch

private data class OnboardingPage(
    val eyebrow: String,
    val title: String,
    val body: String,
    val icon: ImageVector
)

private val pages = listOf(
    OnboardingPage(
        "折叠远方",
        "下一次旅行，你想前往哪里？",
        "不必先填完一张长表。只要说出一个地方，路线会沿着地图慢慢展开。",
        Icons.Rounded.Explore
    ),
    OnboardingPage(
        "地图会记得每次选择",
        "让住处、抵达与沿途，都在地图上彼此照亮",
        "换一家酒店，接驳距离随之更新；换一班车，抵达后的第一段路也会重新排列。",
        Icons.Rounded.Map
    ),
    OnboardingPage(
        "顺序由你决定",
        "先住哪里，还是先怎么抵达，都可以",
        "预算、日期、住宿和交通都能暂时留白。AnyTravel 会从你已经决定的部分继续规划。",
        Icons.AutoMirrored.Rounded.AltRoute
    ),
    OnboardingPage(
        "默认松弛一点",
        "给旅程留一点呼吸，也留下偶遇的余地",
        "留下常用出发地、人数和预算。以后每次规划都可以再改。",
        Icons.Rounded.Bed
    )
)

@Composable
fun OnboardingScreen(
    initialOrigin: String,
    initialBudget: Int,
    initialTravelers: Int,
    onComplete: (String, Int, Int) -> Unit,
    onSkip: () -> Unit
) {
    val pagerState = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()
    var origin by remember { mutableStateOf(initialOrigin) }
    var budget by remember { mutableIntStateOf(initialBudget) }
    var travelers by remember { mutableIntStateOf(initialTravelers) }
    val isLast = pagerState.currentPage == pages.lastIndex

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.92f),
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.secondary.copy(alpha = 0.09f)
                    )
                )
            )
    ) {
        MigratingRouteBackdrop()

        Column(
            Modifier
                .fillMaxSize()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp)
                .padding(top = 18.dp, bottom = 20.dp)
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("AnyTravel", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onBackground)
                TextButton(onClick = onSkip, modifier = Modifier.height(48.dp)) { Text("稍后设置") }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically
            ) { pageIndex ->
                val page = pages[pageIndex]
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    PageIllustration(page.icon, active = pagerState.currentPage == pageIndex)
                    Spacer(Modifier.height(30.dp))
                    Text(
                        page.eyebrow,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        page.title,
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.onBackground,
                        textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(14.dp))
                    Text(
                        page.body,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center
                    )
                    if (pageIndex == pages.lastIndex) {
                        Spacer(Modifier.height(20.dp))
                        InitialPreferences(
                            origin = origin,
                            budget = budget,
                            travelers = travelers,
                            onOriginChange = { origin = it },
                            onBudgetChange = { budget = it },
                            onTravelersChange = { travelers = it }
                        )
                    }
                }
            }

            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                pages.indices.forEach { index ->
                    val selected = index == pagerState.currentPage
                    val width by androidx.compose.animation.core.animateDpAsState(
                        targetValue = if (selected) 28.dp else 8.dp,
                        label = "page indicator"
                    )
                    val color by animateColorAsState(
                        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                        label = "page indicator color"
                    )
                    Box(
                        Modifier
                            .padding(horizontal = 4.dp)
                            .size(width, 8.dp)
                            .clip(CircleShape)
                            .background(color)
                            .semantics { contentDescription = "第${index + 1}页${if (selected) "，当前" else ""}" }
                    )
                }
            }

            Button(
                onClick = {
                    if (isLast) onComplete(origin, budget, travelers)
                    else scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(58.dp),
                shape = RoundedCornerShape(22.dp),
                colors = ButtonDefaults.buttonColors(containerColor = HorizonTeal)
            ) {
                AnimatedContent(targetState = isLast, label = "onboarding button") { finishing ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(if (finishing) "从地图出发" else "继续")
                        Spacer(Modifier.size(8.dp))
                        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null)
                    }
                }
            }
        }
    }
}

@Composable
private fun PageIllustration(icon: ImageVector, active: Boolean) {
    val reduceMotion = LocalReduceMotion.current
    val scale by animateFloatAsState(if (active && !reduceMotion) 1f else 0.94f, label = "illustration scale")
    val rotation by animateFloatAsState(if (active && !reduceMotion) -2f else 0f, label = "illustration rotation")
    Surface(
        modifier = Modifier
            .size(174.dp)
            .scale(scale)
            .rotate(rotation),
        shape = RoundedCornerShape(48.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.88f),
        tonalElevation = 12.dp,
        shadowElevation = 18.dp
    ) {
        Box(contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(TravelOrange.copy(alpha = 0.15f), radius = size.minDimension * 0.23f, center = Offset(size.width * 0.73f, size.height * 0.27f))
                drawLine(HorizonTeal.copy(alpha = 0.20f), Offset(size.width * 0.16f, size.height * 0.78f), Offset(size.width * 0.82f, size.height * 0.30f), strokeWidth = 8f)
            }
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(74.dp))
        }
    }
}

@Composable
private fun InitialPreferences(
    origin: String,
    budget: Int,
    travelers: Int,
    onOriginChange: (String) -> Unit,
    onBudgetChange: (Int) -> Unit,
    onTravelersChange: (Int) -> Unit
) {
    Surface(
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
        tonalElevation = 6.dp
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            OutlinedTextField(
                value = origin,
                onValueChange = onOriginChange,
                label = { Text("常用出发地") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp)
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("每人预算", style = MaterialTheme.typography.labelLarge)
                Text("¥$budget", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
            }
            Slider(
                value = budget.toFloat(),
                onValueChange = { onBudgetChange((it / 100).toInt() * 100) },
                valueRange = 800f..10_000f,
                steps = 45
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("同行人数", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
                IconButton(onClick = { onTravelersChange((travelers - 1).coerceAtLeast(1)) }, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Rounded.Remove, contentDescription = "减少同行人数")
                }
                Text("${travelers}人", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 8.dp))
                IconButton(onClick = { onTravelersChange((travelers + 1).coerceAtMost(8)) }, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Rounded.Add, contentDescription = "增加同行人数")
                }
            }
        }
    }
}

@Composable
private fun MigratingRouteBackdrop() {
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "route drift")
    val drift by if (reduceMotion) {
        remember { mutableFloatStateOf(0f) }
    } else {
        transition.animateFloat(
            initialValue = -12f,
            targetValue = 16f,
            animationSpec = infiniteRepeatable(tween(7_000), RepeatMode.Reverse),
            label = "route drift amount"
        )
    }
    Canvas(Modifier.fillMaxSize()) {
        val routeColor = HorizonTeal.copy(alpha = 0.11f)
        val points = listOf(
            Offset(size.width * 0.02f, size.height * 0.72f + drift),
            Offset(size.width * 0.28f, size.height * 0.58f + drift),
            Offset(size.width * 0.46f, size.height * 0.66f + drift),
            Offset(size.width * 0.70f, size.height * 0.44f + drift),
            Offset(size.width * 0.98f, size.height * 0.36f + drift)
        )
        points.zipWithNext().forEach { (start, end) -> drawLine(routeColor, start, end, strokeWidth = 6f) }
        points.forEach { drawCircle(routeColor, 10f, it) }
    }
}
