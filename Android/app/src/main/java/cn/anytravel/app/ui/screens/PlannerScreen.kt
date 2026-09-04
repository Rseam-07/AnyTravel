package cn.anytravel.app.ui.screens

import android.content.Intent
import androidx.core.net.toUri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.AltRoute
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Launch
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Bed
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.DirectionsBus
import androidx.compose.material.icons.rounded.EditLocationAlt
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.FlightTakeoff
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Map
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Payments
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Route
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Train
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.ExpenseLine
import cn.anytravel.app.model.LocalTravelMode
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.TransportOption
import cn.anytravel.app.model.TransportDirection
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripInterest
import cn.anytravel.app.model.TripPace
import cn.anytravel.app.model.distanceText
import cn.anytravel.app.model.durationText
import cn.anytravel.app.domain.DestinationCatalog
import cn.anytravel.app.ui.PlanTab
import cn.anytravel.app.ui.AccommodationSort
import cn.anytravel.app.ui.PlannerUiState
import cn.anytravel.app.ui.PlannerViewModel
import cn.anytravel.app.data.AssistantProviderMode
import cn.anytravel.app.ui.components.PlannerMap
import cn.anytravel.app.ui.theme.AnyTravelMotion
import cn.anytravel.app.ui.theme.HorizonTeal
import cn.anytravel.app.ui.theme.LocalReduceMotion
import cn.anytravel.app.ui.theme.TravelOrange
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlannerScreen(state: PlannerUiState, viewModel: PlannerViewModel) {
    var panelDragging by remember { mutableStateOf(false) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val containerHeightPx = with(LocalDensity.current) { maxHeight.toPx() }.coerceAtLeast(1f)
        val targetHeight = maxHeight * state.panelFraction
        val panelHeight by animateDpAsState(
            targetValue = targetHeight,
            animationSpec = if (panelDragging) snap() else AnyTravelMotion.settle(),
            label = "planner panel height"
        )
        val dragModifier = Modifier.panelDrag(
            onStart = { panelDragging = true },
            onDelta = { pixels -> viewModel.resizePanelBy(-pixels / containerHeightPx) },
            onEnd = { panelDragging = false }
        )
        PlannerMap(
            plan = state.plan,
            draftCenter = DestinationCatalog.find(state.draft.destination)?.center,
            selectedDay = state.selectedDay,
            selectedTab = state.selectedTab,
            autoCamera = state.autoCamera,
            focusedPlaceID = state.focusedPlaceID,
            onUserGesture = viewModel::userMovedMap,
            modifier = Modifier.fillMaxSize()
        )

        TopChrome(
            destination = state.plan?.draft?.destination ?: state.draft.destination,
            savedCount = state.savedPlans.size,
            onLibrary = { viewModel.showLibrary(true) },
            onSettings = { viewModel.showSettings(true) },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = 14.dp, vertical = 10.dp)
        )

        AnimatedVisibility(
            visible = !state.autoCamera && state.plan != null,
            enter = fadeIn() + scaleIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(top = 82.dp)
        ) {
            AssistChip(
                onClick = viewModel::resumeAutoCamera,
                label = { Text("回到当前路线") },
                leadingIcon = { Icon(Icons.Rounded.LocationOn, contentDescription = null) }
            )
        }

        AnimatedVisibility(
            visible = state.errorMessage != null || state.noticeMessage != null,
            enter = slideInVertically { -it } + fadeIn(),
            exit = slideOutVertically { -it } + fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(top = 78.dp, start = 18.dp, end = 18.dp)
        ) {
            MessageBanner(
                text = state.errorMessage ?: state.noticeMessage.orEmpty(),
                isError = state.errorMessage != null,
                onDismiss = viewModel::dismissMessage
            )
        }

        if (state.plan == null) {
            if (state.panelFraction < 0.30f) {
                CompactDraftPanel(
                    state = state,
                    onDraftChange = viewModel::updateDraft,
                    onGenerate = viewModel::generatePlan,
                    dragHandleModifier = dragModifier,
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(panelHeight)
                )
            } else {
                DraftPanel(
                    state = state,
                    onDraftChange = viewModel::updateDraft,
                    onGenerate = viewModel::generatePlan,
                    dragHandleModifier = dragModifier,
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(panelHeight)
                )
            }
        } else {
            PlanPanel(
                state = state,
                viewModel = viewModel,
                compact = state.panelFraction < 0.30f,
                dragHandleModifier = dragModifier,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(panelHeight)
            )
        }

        if (state.isLoading) {
            PlanningOverlay(destination = state.draft.destination)
        }
    }

    if (state.settingsVisible) {
        SettingsSheet(
            state = state,
            onDismiss = { viewModel.showSettings(false) },
            onSaveURL = viewModel::saveBackendURL,
            onTestURL = viewModel::testBackend,
            onSaveAssistant = viewModel::saveAssistantConfiguration,
            onTestAssistant = viewModel::testAssistantConfiguration,
            onDeleteAssistantKey = viewModel::deleteAssistantAPIKey,
            onRestartWelcome = viewModel::restartOnboarding
        )
    }
    if (state.libraryVisible) {
        SavedTripsSheet(
            plans = state.savedPlans,
            onDismiss = { viewModel.showLibrary(false) },
            onOpen = viewModel::loadPlan,
            onDelete = viewModel::deletePlan
        )
    }
    if (state.attractionPickerVisible) {
        AttractionSelectionSheet(
            state = state,
            onToggle = viewModel::toggleAttraction,
            onConfirm = viewModel::confirmAttractions,
            onSkip = viewModel::skipAttractionSelection,
            onDismiss = viewModel::dismissAttractionSelection
        )
    }
}

@Composable
private fun TopChrome(
    destination: String,
    savedCount: Int,
    onLibrary: () -> Unit,
    onSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        tonalElevation = 8.dp,
        shadowElevation = 12.dp
    ) {
        Row(
            Modifier.padding(start = 14.dp, end = 6.dp, top = 7.dp, bottom = 7.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(shape = RoundedCornerShape(13.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                Icon(
                    Icons.Rounded.Explore,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(9.dp).size(24.dp)
                )
            }
            Column(Modifier.weight(1f).padding(horizontal = 11.dp)) {
                Text("AnyTravel", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                Text(
                    destination.ifBlank { "尚未决定的远方" },
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onLibrary, modifier = Modifier.size(48.dp)) {
                Box {
                    Icon(Icons.Rounded.FolderOpen, contentDescription = "保存的旅程")
                    if (savedCount > 0) {
                        Surface(
                            modifier = Modifier.align(Alignment.TopEnd).size(17.dp),
                            shape = CircleShape,
                            color = TravelOrange
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Text(savedCount.coerceAtMost(9).toString(), color = Color.White, style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
            }
            IconButton(onClick = onSettings, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Rounded.Settings, contentDescription = "设置与数据渠道")
            }
        }
    }
}

@Composable
private fun MessageBanner(text: String, isError: Boolean, onDismiss: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = if (isError) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.primaryContainer,
        tonalElevation = 8.dp,
        shadowElevation = 10.dp
    ) {
        Row(
            Modifier.padding(start = 16.dp, end = 4.dp, top = 9.dp, bottom = 9.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                color = if (isError) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = onDismiss, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Rounded.Close, contentDescription = "关闭提示")
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun CompactDraftPanel(
    state: PlannerUiState,
    onDraftChange: ((TripDraft) -> TripDraft) -> Unit,
    onGenerate: () -> Unit,
    dragHandleModifier: Modifier,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.navigationBarsPadding().imePadding(),
        shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f),
        tonalElevation = 12.dp,
        shadowElevation = 18.dp
    ) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            DragHandle(dragHandleModifier.height(32.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = state.draft.destination,
                    onValueChange = { value -> onDraftChange { it.copy(destination = value) } },
                    placeholder = { Text("下一次旅行，你想前往哪里？") },
                    leadingIcon = { Icon(Icons.Rounded.LocationOn, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(18.dp)
                )
                Button(
                    onClick = onGenerate,
                    enabled = state.draft.destination.isNotBlank(),
                    modifier = Modifier.size(54.dp),
                    contentPadding = PaddingValues(0.dp),
                    shape = CircleShape
                ) { Icon(Icons.Rounded.Route, contentDescription = "让地图规划旅程") }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun DraftPanel(
    state: PlannerUiState,
    onDraftChange: ((TripDraft) -> TripDraft) -> Unit,
    onGenerate: () -> Unit,
    dragHandleModifier: Modifier,
    modifier: Modifier = Modifier
) {
    var showDatePicker by remember { mutableStateOf(false) }
    Surface(
        modifier = modifier.navigationBarsPadding().imePadding(),
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 12.dp,
        shadowElevation = 18.dp
    ) {
        LazyColumn(
            modifier = Modifier.testTag("draft-list"),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item { DragHandle(dragHandleModifier.height(32.dp)) }
            item {
                Text("下一次旅行，你想前往哪里？", style = MaterialTheme.typography.headlineSmall)
                Spacer(Modifier.height(6.dp))
                Text("先说出一个地方，日期、预算、住处和交通都可以稍后再决定。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item {
                OutlinedTextField(
                    value = state.draft.destination,
                    onValueChange = { value -> onDraftChange { it.copy(destination = value) } },
                    label = { Text("目的地") },
                    placeholder = { Text("例如：苏州") },
                    leadingIcon = { Icon(Icons.Rounded.LocationOn, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp)
                )
            }
            item {
                OutlinedTextField(
                    value = state.draft.origin,
                    onValueChange = { value -> onDraftChange { it.copy(origin = value) } },
                    label = { Text("从哪里出发") },
                    placeholder = { Text("可以先留空") },
                    leadingIcon = { Icon(Icons.AutoMirrored.Rounded.AltRoute, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp)
                )
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(
                        onClick = { showDatePicker = true },
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(16.dp)
                    ) {
                        Icon(Icons.Rounded.CalendarMonth, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(state.draft.startDate)
                    }
                    CompactStepper(
                        title = "天数",
                        value = state.draft.dayCount,
                        suffix = "天",
                        range = 1..7,
                        onChange = { count -> onDraftChange { it.copy(dayCount = count) } },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            item {
                Text("旅行强度", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TripPace.entries.forEach { pace ->
                        FilterChip(
                            selected = state.draft.pace == pace,
                            onClick = { onDraftChange { it.copy(pace = pace) } },
                            label = { Text("${pace.title} · ${pace.stopsPerDay}处/天") },
                            leadingIcon = if (state.draft.pace == pace) {{ Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) }} else null
                        )
                    }
                }
            }
            item {
                Text("想把时间留给", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TripInterest.entries.forEach { interest ->
                        val selected = interest in state.draft.interests
                        FilterChip(
                            selected = selected,
                            onClick = {
                                onDraftChange {
                                    val next = if (selected) it.interests - interest else it.interests + interest
                                    it.copy(interests = next.ifEmpty { setOf(TripInterest.CULTURE) })
                                }
                            },
                            label = { Text(interest.title) }
                        )
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CompactStepper(
                        title = "每人预算",
                        value = state.draft.budgetPerPerson,
                        suffix = "元",
                        range = 800..30_000,
                        step = 200,
                        onChange = { value -> onDraftChange { it.copy(budgetPerPerson = value) } },
                        modifier = Modifier.weight(1f)
                    )
                    CompactStepper(
                        title = "同行",
                        value = state.draft.travelers,
                        suffix = "人",
                        range = 1..8,
                        onChange = { value -> onDraftChange { it.copy(travelers = value) } },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            item {
                Text("市内移动", style = MaterialTheme.typography.titleMedium)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LocalTravelMode.entries.forEach { mode ->
                        FilterChip(
                            selected = state.draft.localTravelMode == mode,
                            onClick = { onDraftChange { it.copy(localTravelMode = mode) } },
                            label = { Text(mode.title) }
                        )
                    }
                }
            }
            item {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("这次不需要住宿", style = MaterialTheme.typography.titleMedium)
                        Text("打开后仍会规划景点与交通", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(
                        checked = state.draft.skipAccommodation,
                        onCheckedChange = { checked -> onDraftChange { it.copy(skipAccommodation = checked) } }
                    )
                }
            }
            item {
                Button(
                    onClick = onGenerate,
                    modifier = Modifier.fillMaxWidth().height(58.dp).testTag("generate-plan"),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = HorizonTeal)
                ) {
                    Icon(Icons.Rounded.Route, contentDescription = null)
                    Spacer(Modifier.width(9.dp))
                    Text("让路线在地图上展开")
                }
            }
        }
    }
    if (showDatePicker) {
        val initial = runCatching { LocalDate.parse(state.draft.startDate).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrNull()
        val dateState = rememberDatePickerState(initialSelectedDateMillis = initial)
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    dateState.selectedDateMillis?.let { millis ->
                        val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        onDraftChange { it.copy(startDate = date.toString()) }
                    }
                    showDatePicker = false
                }) { Text("选定") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("取消") } }
        ) { DatePicker(state = dateState) }
    }
}

@Composable
private fun CompactStepper(
    title: String,
    value: Int,
    suffix: String,
    range: IntRange,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    step: Int = 1
) {
    Surface(modifier = modifier, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.62f)) {
        Row(Modifier.height(58.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("$value$suffix", style = MaterialTheme.typography.titleMedium)
            }
            IconButton(onClick = { onChange((value - step).coerceAtLeast(range.first)) }, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Rounded.Remove, contentDescription = "减少$title")
            }
            IconButton(onClick = { onChange((value + step).coerceAtMost(range.last)) }, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Rounded.Add, contentDescription = "增加$title")
            }
        }
    }
}

@Composable
private fun PlanPanel(
    state: PlannerUiState,
    viewModel: PlannerViewModel,
    compact: Boolean,
    dragHandleModifier: Modifier,
    modifier: Modifier = Modifier
) {
    val plan = state.plan ?: return
    Surface(
        modifier = modifier.navigationBarsPadding(),
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f),
        tonalElevation = 12.dp,
        shadowElevation = 20.dp
    ) {
        if (compact) {
            CompactPlanBar(state, viewModel, dragHandleModifier)
            return@Surface
        }
        Column {
            Box(
                dragHandleModifier
                    .fillMaxWidth()
                    .height(26.dp)
                    .clickable(role = Role.Button, onClick = viewModel::togglePanel)
                    .semantics { contentDescription = "拖动或轻点调整方案高度" },
                contentAlignment = Alignment.Center
            ) { DragHandle() }

            Row(Modifier.padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${plan.draft.destination} · ${plan.draft.dayCount}天", style = MaterialTheme.typography.titleLarge)
                    Text("约¥${plan.totalExpense} · ${plan.draft.pace.title}一点", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = viewModel::returnToDraft, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Rounded.EditLocationAlt, contentDescription = "修改规划条件")
                }
                IconButton(onClick = viewModel::saveCurrentPlan, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Rounded.Save, contentDescription = "保存这段旅程")
                }
                IconButton(onClick = viewModel::togglePanel, modifier = Modifier.size(48.dp)) {
                    Icon(if (state.panelFraction > 0.76f) Icons.Rounded.ExpandMore else Icons.Rounded.ExpandLess, contentDescription = "切换面板高度")
                }
            }

            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                PlanTab.entries.forEach { tab ->
                    FilterChip(
                        selected = state.selectedTab == tab,
                        onClick = { viewModel.selectTab(tab) },
                        label = { Text(tab.title) },
                        leadingIcon = { Icon(tab.icon(), contentDescription = null, modifier = Modifier.size(18.dp)) }
                    )
                }
                AssistChip(
                    onClick = viewModel::refreshLiveData,
                    enabled = !state.isRefreshing,
                    label = { Text(if (state.isRefreshing) "正在问价" else "刷新价格") },
                    leadingIcon = { Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(18.dp)) }
                )
            }
            if (state.isRefreshing) LinearProgressIndicator(Modifier.fillMaxWidth())

            AnimatedContent(
                targetState = state.selectedTab,
                modifier = Modifier.weight(1f),
                label = "plan tabs"
            ) { tab ->
                when (tab) {
                    PlanTab.DAYS -> DaysContent(plan, state.selectedDay, viewModel::selectDay)
                    PlanTab.STAYS -> StaysContent(
                        plan = plan,
                        priceCeiling = state.accommodationMaxNightlyPrice,
                        sort = state.accommodationSort,
                        onPriceCeiling = viewModel::setAccommodationPriceCeiling,
                        onSort = viewModel::setAccommodationSort,
                        onSelect = viewModel::selectAccommodation
                    )
                    PlanTab.TRANSPORT -> TransportContent(plan, viewModel::selectTransport)
                    PlanTab.COSTS -> CostsContent(plan)
                }
            }
        }
    }
}

@Composable
private fun CompactPlanBar(state: PlannerUiState, viewModel: PlannerViewModel, dragHandleModifier: Modifier) {
    var request by remember { mutableStateOf("") }
    Column(Modifier.padding(horizontal = 16.dp)) {
        Box(
            dragHandleModifier.fillMaxWidth().height(32.dp).clickable(onClick = viewModel::togglePanel),
            contentAlignment = Alignment.Center
        ) { DragHandle() }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = request,
                onValueChange = { request = it },
                placeholder = { Text(if (state.isAssistantResponding) "正在听懂这句话…" else "想怎么改都可以直接说…") },
                leadingIcon = { Icon(Icons.Rounded.EditLocationAlt, contentDescription = null) },
                singleLine = true,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(18.dp)
            )
            Button(
                onClick = {
                    viewModel.applyQuickAdjustment(request)
                    request = ""
                },
                enabled = request.isNotBlank() && !state.isAssistantResponding,
                modifier = Modifier.size(54.dp),
                contentPadding = PaddingValues(0.dp),
                shape = CircleShape
            ) {
                Icon(
                    if (state.isAssistantResponding) Icons.Rounded.MoreHoriz else Icons.Rounded.Check,
                    contentDescription = "应用这句话"
                )
            }
        }
        Text(
            state.assistantStatusMessage ?: "${state.plan?.draft?.destination.orEmpty()} · 上拉展开完整方案",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 8.dp, top = 3.dp)
        )
    }
}

@Composable
private fun DaysContent(plan: CompletePlan, selectedDay: Int, onSelectDay: (Int) -> Unit) {
    val day = plan.days.getOrNull(selectedDay) ?: plan.days.firstOrNull()
    LazyColumn(contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(plan.days) { item ->
                    FilterChip(selected = item.index == selectedDay, onClick = { onSelectDay(item.index) }, label = { Text(item.title) })
                }
            }
        }
        if (plan.routeIsSchematic) {
            item { DataBoundaryCard("地图上的彩色线段表示游览顺序；Android 首版尚未取得逐路段导航几何，实际道路请用导航页复核。") }
        }
        day?.schedule?.let { schedule ->
            items(schedule, key = { it.id }) { item ->
                Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.56f)) {
                    Row(Modifier.padding(14.dp)) {
                        Text(item.timeText, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.width(104.dp))
                        Column(Modifier.weight(1f)) {
                            Text(item.title, style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.height(4.dp))
                            Text(item.detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        item { DataBoundaryCard(plan.sourceNote) }
    }
}

@Composable
private fun StaysContent(
    plan: CompletePlan,
    priceCeiling: Int?,
    sort: AccommodationSort,
    onPriceCeiling: (Int?) -> Unit,
    onSort: (AccommodationSort) -> Unit,
    onSelect: (String) -> Unit
) {
    if (plan.draft.skipAccommodation) {
        EmptyState(Icons.Rounded.Bed, "这次不需要住宿", "景点、路线和交通仍会继续规划。")
        return
    }
    val filtered = plan.accommodations.filter { option ->
        val price = option.quotes.mapNotNull { it.amountCNY }.minOrNull()
        priceCeiling?.let { ceiling -> price != null && price <= ceiling } ?: true
    }.sortedWith(when (sort) {
        AccommodationSort.RECOMMENDED -> compareByDescending<AccommodationOption> { it.id == plan.selectedAccommodationId }
            .thenBy { it.averageAttractionDistanceMeters }
        AccommodationSort.LOWEST_PRICE -> compareBy { it.quotes.mapNotNull(PriceQuote::amountCNY).minOrNull() ?: Int.MAX_VALUE }
        AccommodationSort.CLOSEST_TO_ATTRACTIONS -> compareBy { it.averageAttractionDistanceMeters }
        AccommodationSort.CLOSEST_TO_TRANSIT -> compareBy { it.hubDistanceMeters }
        AccommodationSort.RATING -> compareByDescending { it.guestRating ?: -1.0 }
    })
    LazyColumn(contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf<Int?>(null, 400, 700, 1000, priceCeiling).distinct().forEach { price ->
                        val title = price?.let { "¥${it}内" } ?: "全部价格"
                        FilterChip(selected = priceCeiling == price, onClick = { onPriceCeiling(price) }, label = { Text(title) })
                    }
                }
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AccommodationSort.entries.forEach { option ->
                        FilterChip(selected = sort == option, onClick = { onSort(option) }, label = { Text(option.title) })
                    }
                }
            }
        }
        if (filtered.isEmpty()) {
            item { DataBoundaryCard("这个筛选下暂时没有带价住处，放宽价格后再看看。") }
        }
        items(filtered, key = { it.id }) { option ->
            AccommodationCard(option, selected = option.id == plan.selectedAccommodationId, onSelect = { onSelect(option.id) })
        }
        item { DataBoundaryCard("实时价格会注明渠道、口径与抓取时间；税费、早餐、取消政策和最终房型以结算页为准。") }
    }
}

@Composable
private fun AccommodationCard(option: AccommodationOption, selected: Boolean, onSelect: () -> Unit) {
    val context = LocalContext.current
    val best = option.quotes.filter { it.isCurrentPrice() }.minByOrNull { it.amountCNY ?: Int.MAX_VALUE }
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onSelect, role = Role.RadioButton),
        shape = RoundedCornerShape(22.dp),
        color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
        border = if (selected) androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary) else null
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface) {
                    Icon(Icons.Rounded.Bed, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(10.dp))
                }
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(option.name, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        if (selected) Text("已选择", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium)
                    }
                    Text(option.address, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                }
                Text(best?.priceText() ?: "待核价", color = if (best != null) TravelOrange else MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.titleMedium)
            }
            Spacer(Modifier.height(11.dp))
            option.recommendationReasons.forEach { reason ->
                Text("· $reason", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(10.dp))
            option.quotes.forEach { quote -> QuoteRow(quote, onOpen = { quote.bookingURL?.let { openURL(context, it) } }) }
        }
    }
}

@Composable
private fun TransportContent(plan: CompletePlan, onSelect: (String) -> Unit) {
    var direction by remember(plan.id) { mutableStateOf(TransportDirection.OUTBOUND) }
    var mode by remember(plan.id) { mutableStateOf<LongDistanceMode?>(null) }
    val visible = plan.transports.filter { option ->
        option.direction == direction && (mode == null || option.mode == mode)
    }
    LazyColumn(contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TransportDirection.entries.forEach { option ->
                        FilterChip(selected = direction == option, onClick = { direction = option }, label = { Text(option.title) })
                    }
                }
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf<LongDistanceMode?>(null, LongDistanceMode.TRAIN, LongDistanceMode.FLIGHT, LongDistanceMode.DRIVING).forEach { option ->
                        FilterChip(selected = mode == option, onClick = { mode = option }, label = { Text(option?.title ?: "全部方式") })
                    }
                }
            }
        }
        if (visible.isEmpty()) item { DataBoundaryCard("这一程暂时没有匹配班次；可切换交通方式或刷新当日数据。") }
        items(visible, key = { it.id }) { option ->
            TransportCard(option, selected = option.id == plan.selectedTransportId, onSelect = { onSelect(option.id) })
        }
        item { DataBoundaryCard("交通推荐会在取得实时班次后按门到门耗时、价格、换乘和酒店接驳重新排序。") }
    }
}

@Composable
private fun TransportCard(option: TransportOption, selected: Boolean, onSelect: () -> Unit) {
    val context = LocalContext.current
    val quote = option.quotes.filter { it.isCurrentPrice() }.minByOrNull { it.amountCNY ?: Int.MAX_VALUE }
    val icon = when (option.mode) {
        LongDistanceMode.TRAIN -> Icons.Rounded.Train
        LongDistanceMode.FLIGHT -> Icons.Rounded.FlightTakeoff
        LongDistanceMode.DRIVING -> Icons.Rounded.DirectionsBus
    }
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onSelect, role = Role.RadioButton),
        shape = RoundedCornerShape(22.dp),
        color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
        border = if (selected) androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary) else null
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                    Text(option.title, style = MaterialTheme.typography.titleMedium)
                    val time = listOfNotNull(option.departureTime, option.arrivalTime).joinToString("–")
                    Text(
                        if (time.isNotBlank()) time else "具体发到时间待实时查询",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(quote?.priceText() ?: "待核价", color = if (quote?.amountCNY != null) TravelOrange else MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.titleMedium)
            }
            Spacer(Modifier.height(10.dp))
            option.recommendationReasons.forEach { Text("· $it", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            option.durationMinutes?.let { Text("· 预计总耗时基线 ${it.durationText()}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            option.quotes.forEach { item -> QuoteRow(item, onOpen = { item.bookingURL?.let { url -> openURL(context, url) } }) }
        }
    }
}

@Composable
private fun QuoteRow(quote: PriceQuote, onOpen: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(top = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text("${quote.sourceLabel ?: quote.provider} · ${quote.kind.title}", style = MaterialTheme.typography.labelLarge)
            Text(
                buildString {
                    quote.capturedAt?.let { append("${it.take(16).replace('T', ' ')} 抓取 · ") }
                    append(quote.note)
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
        quote.amountCNY?.let {
            Text(quote.priceText(), color = TravelOrange, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(horizontal = 6.dp))
        }
        if (quote.bookingURL != null) {
            TextButton(onClick = onOpen, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(if (quote.amountCNY == null) "去查询" else "查看")
                Icon(Icons.AutoMirrored.Rounded.Launch, contentDescription = null, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun CostsContent(plan: CompletePlan) {
    LazyColumn(contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Surface(shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Payments, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(30.dp))
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        Text("当前方案总计", style = MaterialTheme.typography.labelLarge)
                        Text("¥${plan.totalExpense}", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    Text("${plan.draft.travelers}人", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        items(plan.expenses, key = { it.id }) { ExpenseRow(it) }
        item { DataBoundaryCard("预算预留用于把方案补完整，不代表平台报价；取得实时价后，对应项目会自动替换并重新合计。") }
    }
}

@Composable
private fun ExpenseRow(line: ExpenseLine) {
    Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(line.title, style = MaterialTheme.typography.titleMedium)
                Text("${line.detail} · ${line.source.title}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("¥${line.amountCNY}", style = MaterialTheme.typography.titleMedium)
        }
    }
}

@Composable
private fun DataBoundaryCard(text: String) {
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.55f)) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.padding(14.dp))
    }
}

@Composable
private fun EmptyState(icon: ImageVector, title: String, body: String) {
    Column(Modifier.fillMaxSize().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(46.dp))
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.titleLarge)
        Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AttractionSelectionSheet(
    state: PlannerUiState,
    onToggle: (String) -> Unit,
    onConfirm: () -> Unit,
    onSkip: () -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxHeight(0.92f)) {
            Column(Modifier.padding(horizontal = 22.dp, vertical = 8.dp)) {
                Text("先把想去的地方圈出来", style = MaterialTheme.typography.headlineSmall)
                Spacer(Modifier.height(6.dp))
                Text(
                    "按公开搜索与城市热度由热门到冷门排列。少选会补入相邻地点，多选会保留并提示行程压力。",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    if (state.selectedAttractionIDs.isEmpty()) "尚未勾选，可以直接交给 AnyTravel" else "已勾选 ${state.selectedAttractionIDs.size} 处主游览点",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            LazyColumn(
                modifier = Modifier.weight(1f).testTag("attraction-list"),
                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(state.attractionCandidates, key = { it.id }) { place ->
                    val selected = place.id in state.selectedAttractionIDs
                    Surface(
                        modifier = Modifier.fillMaxWidth().clickable(role = Role.Checkbox) { onToggle(place.id) },
                        shape = RoundedCornerShape(20.dp),
                        color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.56f),
                        border = if (selected) androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary) else null
                    ) {
                        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Surface(shape = CircleShape, color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface) {
                                Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) {
                                    if (selected) Icon(Icons.Rounded.Check, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary)
                                    else Text(place.popularityRank.toString(), style = MaterialTheme.typography.labelLarge)
                                }
                            }
                            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                                Text(place.name, style = MaterialTheme.typography.titleMedium)
                                Text(place.introduction, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            }
                            Text(place.interest.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
            Row(
                Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 18.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                OutlinedButton(onClick = onSkip, modifier = Modifier.weight(1f).height(54.dp), shape = RoundedCornerShape(18.dp)) {
                    Text("跳过，交给 AnyTravel")
                }
                Button(onClick = onConfirm, modifier = Modifier.weight(1f).height(54.dp), shape = RoundedCornerShape(18.dp)) {
                    Text(if (state.selectedAttractionIDs.isEmpty()) "按热门生成" else "按所选生成")
                }
            }
        }
    }
}

@Composable
private fun PlanningOverlay(destination: String) {
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "planning flight")
    val progress by if (reduceMotion) {
        remember { mutableFloatStateOf(0.5f) }
    } else {
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1_800), RepeatMode.Restart), label = "planning flight progress")
    }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f)), contentAlignment = Alignment.Center) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f),
            tonalElevation = 12.dp,
            shadowElevation = 20.dp
        ) {
            Column(Modifier.padding(horizontal = 34.dp, vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Rounded.FlightTakeoff,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(42.dp).rotate(progress * 9f - 4.5f)
                )
                Spacer(Modifier.height(16.dp))
                Text("正在把${destination}折进地图", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(7.dp))
                Text("寻找地点、住处与抵达方式", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(18.dp))
                LinearProgressIndicator(progress = { progress }, modifier = Modifier.width(210.dp).clip(CircleShape))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(
    state: PlannerUiState,
    onDismiss: () -> Unit,
    onSaveURL: (String) -> Unit,
    onTestURL: (String) -> Unit,
    onSaveAssistant: (AssistantProviderMode, String, String, String) -> Unit,
    onTestAssistant: (AssistantProviderMode, String, String, String) -> Unit,
    onDeleteAssistantKey: () -> Unit,
    onRestartWelcome: () -> Unit
) {
    val context = LocalContext.current
    var url by remember(state.backendURL) { mutableStateOf(state.backendURL) }
    var assistantMode by remember(state.assistantMode) { mutableStateOf(state.assistantMode) }
    var customBaseURL by remember(state.customAssistantBaseURL) { mutableStateOf(state.customAssistantBaseURL) }
    var customModel by remember(state.customAssistantModel) { mutableStateOf(state.customAssistantModel) }
    var customAPIKey by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        LazyColumn(
            modifier = Modifier.testTag("settings-list"),
            contentPadding = PaddingValues(start = 22.dp, end = 22.dp, bottom = 34.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                Text("旅途偏好与价格渠道", style = MaterialTheme.typography.headlineSmall)
                Text("内置公开数据源会直接读取当日酒店价、航班价与 12306 班次；自建节点可继续补充更多渠道。", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
            }
            item {
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    label = { Text("AnyTravel 报价节点") },
                    placeholder = { Text("例如 http://10.0.2.2:8787/") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp)
                )
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = { onSaveURL(url) }, modifier = Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(16.dp)) { Text("保存地址") }
                    OutlinedButton(onClick = { onTestURL(url) }, modifier = Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(16.dp)) { Text("测试连接") }
                }
            }
            state.backendHealthy?.let { healthy ->
                item {
                    DataBoundaryCard(if (healthy) "节点连接正常，可以刷新酒店与交通数据。" else "节点没有回应，请检查地址、网络与服务状态。")
                }
            }
            item { HorizontalDivider() }
            item {
                Text("自然语言向导", style = MaterialTheme.typography.titleLarge)
                Text("你可以随便说一句，向导会把日期、预算、节奏、交通与地图动作拆成可执行的选择。", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 5.dp))
            }
            item {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AssistantProviderMode.entries.forEach { mode ->
                        FilterChip(
                            selected = assistantMode == mode,
                            onClick = { assistantMode = mode },
                            label = { Text(mode.title) }
                        )
                    }
                }
            }
            if (assistantMode == AssistantProviderMode.MANAGED) {
                item {
                    DataBoundaryCard("默认由 GLM-5.3-Flash 理解旅途语言；填写伴随服务地址时优先经由你的节点，否则由应用内置连接直达。")
                }
            } else {
                item {
                    OutlinedTextField(
                        value = customBaseURL,
                        onValueChange = { customBaseURL = it },
                        label = { Text("OpenAI 兼容服务地址") },
                        placeholder = { Text("https://…/v1") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp)
                    )
                }
                item {
                    OutlinedTextField(
                        value = customModel,
                        onValueChange = { customModel = it },
                        label = { Text("模型名称") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp)
                    )
                }
                item {
                    OutlinedTextField(
                        value = customAPIKey,
                        onValueChange = { customAPIKey = it },
                        label = { Text("API Key") },
                        placeholder = { Text(if (state.hasCustomAssistantAPIKey) "已安全保存，留空即可沿用" else "只保存在这台设备") },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp)
                    )
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = { onSaveAssistant(assistantMode, customBaseURL, customModel, customAPIKey) },
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(16.dp)
                    ) { Text("保存向导") }
                    OutlinedButton(
                        onClick = { onTestAssistant(assistantMode, customBaseURL, customModel, customAPIKey) },
                        enabled = !state.isAssistantResponding,
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(16.dp)
                    ) { Text(if (state.isAssistantResponding) "正在确认" else "测试向导") }
                }
            }
            if (assistantMode == AssistantProviderMode.CUSTOM && state.hasCustomAssistantAPIKey) {
                item {
                    TextButton(onClick = onDeleteAssistantKey, modifier = Modifier.fillMaxWidth()) {
                        Text("删除这台设备上的自定义 API Key")
                    }
                }
            }
            state.assistantStatusMessage?.let { message ->
                item { DataBoundaryCard(message) }
            }
            item { HorizontalDivider() }
            item {
                Text("平台入口", style = MaterialTheme.typography.titleLarge)
                Text("卡片会标明来源和抓取时间；打开渠道后由平台完成登录、锁价与下单。", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 5.dp))
            }
            item { ProviderLink("携程", "酒店与交通", "https://m.ctrip.com/html5/") { openURL(context, it) } }
            item { ProviderLink("去哪儿", "酒店与交通", "https://touch.qunar.com/") { openURL(context, it) } }
            item { ProviderLink("铁路12306", "官方购票页", "https://www.12306.cn/") { openURL(context, it) } }
            item { HorizontalDivider() }
            item {
                Text("这张地图从哪里生长", style = MaterialTheme.typography.titleLarge)
                Text("内置攻略经过城市归属、重复地点和代表性地标校验；营业、预约和票价会按出行日期重新查询。", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 5.dp))
            }
            item { ProviderLink("OpenStreetMap", "地图与地点 · ODbL", "https://www.openstreetmap.org/copyright") { openURL(context, it) } }
            item { ProviderLink("Wikidata", "公共知识 · CC0", "https://www.wikidata.org/wiki/Wikidata:Licensing") { openURL(context, it) } }
            item { ProviderLink("Data by Audiala", "旅行资料 · CC BY 4.0", "https://audiala.com/") { openURL(context, it) } }
            item { ProviderLink("文化和旅游部", "A 级景区名录校验", "https://sjfw.mct.gov.cn/site/dataservice/base") { openURL(context, it) } }
            item { HorizontalDivider() }
            item {
                OutlinedButton(
                    onClick = onRestartWelcome,
                    modifier = Modifier.fillMaxWidth().height(52.dp).testTag("restart-welcome"),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Icon(Icons.Rounded.Explore, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("重新阅读欢迎与初始设置")
                }
            }
            item { DataBoundaryCard("地图底图由 OpenFreeMap、OpenMapTiles 与 OpenStreetMap 数据提供；归属信息始终保留在地图上。") }
        }
    }
}

@Composable
private fun ProviderLink(name: String, detail: String, url: String, onOpen: (String) -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable { onOpen(url) },
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
    ) {
        Row(Modifier.padding(start = 16.dp, end = 6.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleMedium)
                Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = { onOpen(url) }, modifier = Modifier.size(48.dp)) { Icon(Icons.AutoMirrored.Rounded.Launch, contentDescription = "打开$name") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SavedTripsSheet(
    plans: List<CompletePlan>,
    onDismiss: () -> Unit,
    onOpen: (CompletePlan) -> Unit,
    onDelete: (String) -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(horizontal = 22.dp)) {
            Text("折回来的远方", style = MaterialTheme.typography.headlineSmall)
            Text("保存在这台设备上的行程", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 5.dp, bottom = 14.dp))
        }
        if (plans.isEmpty()) {
            EmptyState(Icons.Rounded.FolderOpen, "还没有保存的旅程", "生成方案后，点一下保存，远方就会留在这里。")
        } else {
            LazyColumn(
                contentPadding = PaddingValues(start = 22.dp, end = 22.dp, bottom = 34.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(plans, key = { it.id }) { plan ->
                    Surface(
                        modifier = Modifier.fillMaxWidth().clickable { onOpen(plan) },
                        shape = RoundedCornerShape(20.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
                    ) {
                        Row(Modifier.padding(start = 16.dp, end = 4.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) {
                                Icon(Icons.Rounded.Map, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(10.dp))
                            }
                            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                                Text(plan.draft.destination, style = MaterialTheme.typography.titleMedium)
                                Text("${plan.draft.dayCount}天 · ${plan.draft.travelers}人 · 约¥${plan.totalExpense}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            IconButton(onClick = { onDelete(plan.id) }, modifier = Modifier.size(48.dp)) {
                                Icon(Icons.Rounded.DeleteOutline, contentDescription = "删除${plan.draft.destination}行程")
                            }
                            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DragHandle(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(Modifier.size(38.dp, 5.dp).clip(CircleShape).background(MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)))
    }
}

private fun Modifier.panelDrag(
    onStart: () -> Unit,
    onDelta: (Float) -> Unit,
    onEnd: () -> Unit
): Modifier = pointerInput(onStart, onDelta, onEnd) {
    detectVerticalDragGestures(
        onDragStart = { onStart() },
        onDragEnd = onEnd,
        onDragCancel = onEnd
    ) { change, amount ->
        change.consume()
        onDelta(amount)
    }
}

private fun PlanTab.icon(): ImageVector = when (this) {
    PlanTab.DAYS -> Icons.Rounded.Route
    PlanTab.STAYS -> Icons.Rounded.Bed
    PlanTab.TRANSPORT -> Icons.Rounded.Train
    PlanTab.COSTS -> Icons.Rounded.Payments
}

private fun PriceQuote.priceText(): String {
    val base = displayPriceText ?: amountCNY?.let { "¥$it" } ?: return "待核价"
    return if ('/' in base) base else when (unit) {
        QuoteUnit.PER_NIGHT -> "$base/晚"
        QuoteUnit.PER_PERSON -> "$base/人"
        QuoteUnit.TOTAL -> "$base/总价"
    }
}

private fun PriceQuote.isCurrentPrice(): Boolean =
    amountCNY != null && (kind == QuoteKind.LIVE || kind == QuoteKind.INDICATIVE)

private fun QuoteUnit.shortTitle(): String = when (this) {
    QuoteUnit.PER_NIGHT -> "晚"
    QuoteUnit.PER_PERSON -> "人"
    QuoteUnit.TOTAL -> "总"
}

private fun openURL(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
