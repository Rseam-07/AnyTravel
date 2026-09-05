package cn.anytravel.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.compose.runtime.Immutable
import cn.anytravel.app.data.AppRepository
import cn.anytravel.app.data.AssistantConfiguration
import cn.anytravel.app.data.AssistantProviderMode
import cn.anytravel.app.data.DirectPricingClient
import cn.anytravel.app.data.OpenRouteClient
import cn.anytravel.app.data.PricingClient
import cn.anytravel.app.data.PricingRefreshResult
import cn.anytravel.app.data.TravelAssistantAction
import cn.anytravel.app.data.TravelAssistantClient
import cn.anytravel.app.data.TravelAssistantContext
import cn.anytravel.app.domain.DestinationResolver
import cn.anytravel.app.domain.PlanBuilder
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.ItineraryDay
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.LocalTravelMode
import cn.anytravel.app.model.TripInterest
import cn.anytravel.app.model.TripPace
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope

enum class PlanTab(val title: String) {
    DAYS("日程"),
    STAYS("住宿"),
    TRANSPORT("交通"),
    COSTS("费用")
}

enum class MapAppearance(val title: String) {
    SYSTEM("随系统"),
    STREET("街道"),
    QUIET("素色"),
    NIGHT("夜色")
}

enum class AccommodationSort(val title: String) {
    RECOMMENDED("综合推荐"),
    LOWEST_PRICE("价格最低"),
    CLOSEST_TO_ATTRACTIONS("离景点更近"),
    CLOSEST_TO_TRANSIT("离枢纽更近"),
    RATING("评分更高")
}

enum class AccommodationAmenity(val title: String, val terms: Set<String>) {
    BREAKFAST("含早餐", setOf("早餐", "breakfast")),
    WIFI("无线网络", setOf("wifi", "wi-fi", "无线", "网络")),
    PARKING("停车", setOf("停车", "parking")),
    POOL("泳池", setOf("泳池", "游泳", "pool")),
    FAMILY("亲子", setOf("亲子", "儿童", "family", "kids"))
}

@Immutable
data class PlannerUiState(
    val onboardingComplete: Boolean,
    val draft: TripDraft,
    val plan: CompletePlan? = null,
    val savedPlans: List<CompletePlan> = emptyList(),
    val backendURL: String = "",
    val assistantMode: AssistantProviderMode = AssistantProviderMode.MANAGED,
    val customAssistantBaseURL: String = "https://open.bigmodel.cn/api/paas/v4",
    val customAssistantModel: String = "glm-5.3-flash",
    val hasCustomAssistantAPIKey: Boolean = false,
    val isAssistantResponding: Boolean = false,
    val assistantStatusMessage: String? = null,
    val selectedTab: PlanTab = PlanTab.DAYS,
    val selectedDay: Int = 0,
    val panelFraction: Float = 0.62f,
    val autoCamera: Boolean = true,
    val cameraRequestToken: Int = 0,
    val northRequestToken: Int = 0,
    val mapAppearance: MapAppearance = MapAppearance.SYSTEM,
    val focusedPlaceID: String? = null,
    val canUndoItinerary: Boolean = false,
    val canRedoItinerary: Boolean = false,
    val accommodationMaxNightlyPrice: Int? = null,
    val accommodationSort: AccommodationSort = AccommodationSort.RECOMMENDED,
    val accommodationMinimumRating: Double? = null,
    val accommodationMaximumAttractionDistanceMeters: Int? = null,
    val accommodationAmenity: AccommodationAmenity? = null,
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    val settingsVisible: Boolean = false,
    val libraryVisible: Boolean = false,
    val attractionPickerVisible: Boolean = false,
    val attractionCandidates: List<TravelPlace> = emptyList(),
    val selectedAttractionIDs: Set<String> = emptySet(),
    val pendingDestinationPack: DestinationPack? = null,
    val errorMessage: String? = null,
    val noticeMessage: String? = null,
    val backendHealthy: Boolean? = null
)

class PlannerViewModel(
    private val repository: AppRepository,
    private val resolver: DestinationResolver,
    private val builder: PlanBuilder = PlanBuilder(),
    private val pricingClient: PricingClient = PricingClient(),
    private val directPricingClient: DirectPricingClient = DirectPricingClient(),
    private val assistantClient: TravelAssistantClient = TravelAssistantClient(),
    private val routeClient: OpenRouteClient = OpenRouteClient()
) : ViewModel() {
    private var pricingRefreshToken = 0
    private var routeRefreshToken = 0
    private var planningJob: Job? = null
    private var pricingRefreshJob: Job? = null
    private var routeRefreshJob: Job? = null
    private var assistantJob: Job? = null
    private var mapPinJob: Job? = null
    private var manuallySelectedAccommodationId: String? = null
    private var manuallySelectedTransportId: String? = null
    private val itineraryUndo = java.util.ArrayDeque<CompletePlan>()
    private val itineraryRedo = java.util.ArrayDeque<CompletePlan>()
    private val initialAssistantConfiguration = repository.assistantConfiguration()
    private val _state = MutableStateFlow(
        PlannerUiState(
            onboardingComplete = repository.isOnboardingComplete(),
            draft = repository.loadDraft(),
            savedPlans = repository.loadPlans(),
            backendURL = repository.backendURL(),
            assistantMode = initialAssistantConfiguration.mode,
            customAssistantBaseURL = initialAssistantConfiguration.customBaseURL,
            customAssistantModel = initialAssistantConfiguration.customModel,
            hasCustomAssistantAPIKey = initialAssistantConfiguration.hasCustomAPIKey
        )
    )
    val state: StateFlow<PlannerUiState> = _state.asStateFlow()

    fun completeOnboarding(origin: String, budgetPerPerson: Int, travelers: Int) {
        repository.completeOnboarding(origin, budgetPerPerson, travelers)
        _state.update {
            it.copy(
                onboardingComplete = true,
                draft = repository.loadDraft(),
                errorMessage = null
            )
        }
    }

    fun skipOnboarding() {
        repository.skipOnboarding()
        _state.update { it.copy(onboardingComplete = true) }
    }

    fun restartOnboarding() {
        repository.resetOnboarding()
        _state.update { it.copy(onboardingComplete = false, settingsVisible = false) }
    }

    fun updateDraft(transform: (TripDraft) -> TripDraft) {
        val draft = transform(_state.value.draft)
        repository.saveDraft(draft)
        _state.update { it.copy(draft = draft, errorMessage = null, noticeMessage = null) }
    }

    fun generatePlan() {
        val draft = _state.value.draft
        if (draft.destination.isBlank()) {
            _state.update { it.copy(errorMessage = "先告诉我想去哪里，其他选择都可以稍后再补") }
            return
        }
        routeRefreshToken += 1
        routeRefreshJob?.cancel()
        planningJob?.cancel()
        planningJob = viewModelScope.launch {
            _state.update { it.copy(isLoading = true, errorMessage = null, noticeMessage = null, autoCamera = true) }
            try {
                val pack = resolver.resolve(draft)
                _state.update {
                    it.copy(
                        isLoading = false,
                        attractionPickerVisible = true,
                        attractionCandidates = pack.places.sortedBy { place -> place.popularityRank },
                        selectedAttractionIDs = it.plan?.selectedPlaceIDs.orEmpty()
                            .intersect(pack.places.mapTo(mutableSetOf()) { place -> place.id }),
                        pendingDestinationPack = pack,
                        noticeMessage = null
                    )
                }
            } catch (_: CancellationException) {
                return@launch
            } catch (error: Throwable) {
                _state.update { it.copy(isLoading = false, errorMessage = error.message ?: "暂时无法生成路线，请稍后重试") }
            }
        }
    }

    fun toggleAttraction(id: String) {
        _state.update { state ->
            val next = if (id in state.selectedAttractionIDs) {
                state.selectedAttractionIDs - id
            } else {
                state.selectedAttractionIDs + id
            }
            state.copy(selectedAttractionIDs = next)
        }
    }

    fun confirmAttractions() {
        finishPlanning(selectionWasSkipped = false)
    }

    fun skipAttractionSelection() {
        finishPlanning(selectionWasSkipped = true)
    }

    fun dismissAttractionSelection() {
        _state.update { it.copy(attractionPickerVisible = false, pendingDestinationPack = null) }
    }

    fun editAttractions() {
        val currentPlan = _state.value.plan ?: return
        planningJob?.cancel()
        planningJob = viewModelScope.launch {
            _state.update { it.copy(isLoading = true, errorMessage = null, noticeMessage = null) }
            try {
                val pack = resolver.resolve(currentPlan.draft)
                val currentNames = currentPlan.days.flatMap { it.stops }
                    .mapTo(mutableSetOf()) { normalizedPlaceName(it.name) }
                val selected = pack.places
                    .filter { normalizedPlaceName(it.name) in currentNames }
                    .mapTo(mutableSetOf()) { it.id }
                _state.update {
                    it.copy(
                        isLoading = false,
                        attractionPickerVisible = true,
                        attractionCandidates = pack.places.sortedBy { place -> place.popularityRank },
                        selectedAttractionIDs = selected,
                        pendingDestinationPack = pack,
                        noticeMessage = "已把现在的停靠点重新摊开"
                    )
                }
            } catch (_: CancellationException) {
                return@launch
            } catch (error: Throwable) {
                _state.update { it.copy(isLoading = false, errorMessage = error.message ?: "暂时无法重新寻找景点") }
            }
        }
    }

    private fun finishPlanning(selectionWasSkipped: Boolean) {
        val current = _state.value
        val pack = current.pendingDestinationPack ?: return
        val selected = if (selectionWasSkipped) emptySet() else current.selectedAttractionIDs
        val plan = builder.build(current.draft, pack, selected, selectionWasSkipped)
        manuallySelectedAccommodationId = null
        manuallySelectedTransportId = null
        clearItineraryHistory()
        _state.update {
            it.copy(
                plan = plan,
                attractionPickerVisible = false,
                pendingDestinationPack = null,
                selectedTab = PlanTab.DAYS,
                selectedDay = 0,
                canUndoItinerary = false,
                canRedoItinerary = false,
                panelFraction = 0.58f,
                noticeMessage = if (selectionWasSkipped) {
                    "已按热度、兴趣与距离补齐一条轻松路线"
                } else {
                    "已优先为你选中的${selected.size}处留出时间"
                }
            )
        }
        startPricingRefresh(plan)
        startRouteRefresh(plan)
    }

    fun returnToDraft() {
        pricingRefreshToken += 1
        routeRefreshToken += 1
        planningJob?.cancel()
        pricingRefreshJob?.cancel()
        routeRefreshJob?.cancel()
        assistantJob?.cancel()
        mapPinJob?.cancel()
        manuallySelectedAccommodationId = null
        manuallySelectedTransportId = null
        clearItineraryHistory()
        _state.update {
            it.copy(
                plan = null,
                panelFraction = 0.62f,
                isRefreshing = false,
                canUndoItinerary = false,
                canRedoItinerary = false,
                errorMessage = null,
                noticeMessage = null
            )
        }
    }

    fun selectDay(index: Int) {
        _state.update { it.copy(selectedDay = index, selectedTab = PlanTab.DAYS, panelFraction = 0.58f, autoCamera = true, focusedPlaceID = null) }
    }

    fun beginMapPinSelection() {
        if (_state.value.plan == null) {
            _state.update { it.copy(noticeMessage = "先生成一段行程，再从地图上拾取停靠点") }
            return
        }
        _state.update {
            it.copy(
                panelFraction = 0.18f,
                autoCamera = false,
                noticeMessage = "长按地图上的位置，它会成为当前一天的新停靠"
            )
        }
    }

    fun addMapPin(coordinate: Coordinate) {
        val original = _state.value.plan ?: return
        if (original.days.isEmpty()) {
            _state.update { it.copy(errorMessage = "这段行程还没有可放置地点的日期") }
            return
        }
        mapPinJob?.cancel()
        mapPinJob = viewModelScope.launch {
            _state.update { it.copy(noticeMessage = "正在辨认你从地图上拾起的位置…") }
            val place = resolver.reverse(coordinate)
            val current = _state.value.plan?.takeIf { it.id == original.id } ?: return@launch
            val dayIndex = _state.value.selectedDay.coerceIn(current.days.indices)
            val duplicate = current.days.flatMap { it.stops }.any { existing ->
                existing.coordinate.distanceTo(place.coordinate) <= 45 ||
                    (existing.coordinate.distanceTo(place.coordinate) <= 250 &&
                        normalizedPlaceName(existing.name) == normalizedPlaceName(place.name))
            }
            if (duplicate) {
                _state.update { it.copy(errorMessage = "这个位置已经在行程里了", noticeMessage = null) }
                return@launch
            }
            val days = current.days.toMutableList()
            val day = days[dayIndex]
            days[dayIndex] = day.copy(stops = day.stops + place)
            commitItineraryEdit(current, days, dayIndex, "已把${place.name}放进第${dayIndex + 1}天")
            _state.update { it.copy(focusedPlaceID = place.id) }
        }
    }

    fun movePlaceWithinDay(dayIndex: Int, placeID: String, offset: Int) {
        val plan = _state.value.plan ?: return
        val day = plan.days.getOrNull(dayIndex) ?: return
        val sourceIndex = day.stops.indexOfFirst { it.id == placeID }
        if (sourceIndex < 0) return
        val targetIndex = (sourceIndex + offset).coerceIn(0, day.stops.lastIndex)
        if (targetIndex == sourceIndex) return
        val stops = day.stops.toMutableList()
        val place = stops.removeAt(sourceIndex)
        stops.add(targetIndex, place)
        val days = plan.days.toMutableList().apply { this[dayIndex] = day.copy(stops = stops) }
        commitItineraryEdit(plan, days, dayIndex, "已调整${place.name}在第${dayIndex + 1}天的先后顺序")
    }

    fun movePlaceToAdjacentDay(dayIndex: Int, placeID: String, offset: Int) {
        val plan = _state.value.plan ?: return
        val targetDay = dayIndex + offset
        if (targetDay !in plan.days.indices) return
        val source = plan.days.getOrNull(dayIndex) ?: return
        val place = source.stops.firstOrNull { it.id == placeID } ?: return
        val days = plan.days.toMutableList()
        days[dayIndex] = source.copy(stops = source.stops.filterNot { it.id == placeID })
        val target = days[targetDay]
        days[targetDay] = target.copy(stops = (target.stops + place).distinctBy { it.id })
        commitItineraryEdit(plan, days, targetDay, "已把${place.name}移到第${targetDay + 1}天，并重新计算当天时间")
    }

    fun removePlace(dayIndex: Int, placeID: String) {
        val plan = _state.value.plan ?: return
        if (plan.days.sumOf { it.stops.size } <= 1) {
            _state.update { it.copy(errorMessage = "至少留下一处想去的地方") }
            return
        }
        val source = plan.days.getOrNull(dayIndex) ?: return
        val place = source.stops.firstOrNull { it.id == placeID } ?: return
        val days = plan.days.toMutableList().apply {
            this[dayIndex] = source.copy(stops = source.stops.filterNot { it.id == placeID })
        }
        commitItineraryEdit(plan, days, dayIndex, "已移去${place.name}，路线和费用正在随之收拢")
    }

    fun undoItineraryEdit() {
        val current = _state.value.plan ?: return
        val previous = itineraryUndo.pollLast() ?: return
        pushHistory(itineraryRedo, current)
        publishRestoredPlan(previous, "已撤回上一次行程修改")
    }

    fun redoItineraryEdit() {
        val current = _state.value.plan ?: return
        val next = itineraryRedo.pollLast() ?: return
        pushHistory(itineraryUndo, current)
        publishRestoredPlan(next, "已重新应用这次行程修改")
    }

    private fun commitItineraryEdit(
        original: CompletePlan,
        days: List<ItineraryDay>,
        selectedDay: Int,
        message: String
    ) {
        pushHistory(itineraryUndo, original)
        itineraryRedo.clear()
        val revised = builder.updateItinerary(original, days, message)
        _state.update {
            it.copy(
                plan = revised,
                selectedDay = selectedDay.coerceIn(revised.days.indices),
                selectedTab = PlanTab.DAYS,
                panelFraction = 0.72f,
                autoCamera = true,
                focusedPlaceID = null,
                canUndoItinerary = itineraryUndo.isNotEmpty(),
                canRedoItinerary = false,
                noticeMessage = message
            )
        }
        startRouteRefresh(revised)
        startPricingRefresh(revised)
    }

    private fun publishRestoredPlan(plan: CompletePlan, message: String) {
        _state.update {
            it.copy(
                plan = plan,
                selectedDay = it.selectedDay.coerceIn(plan.days.indices),
                selectedTab = PlanTab.DAYS,
                panelFraction = 0.72f,
                autoCamera = true,
                focusedPlaceID = null,
                canUndoItinerary = itineraryUndo.isNotEmpty(),
                canRedoItinerary = itineraryRedo.isNotEmpty(),
                noticeMessage = message
            )
        }
        startRouteRefresh(plan)
        startPricingRefresh(plan)
    }

    private fun pushHistory(stack: java.util.ArrayDeque<CompletePlan>, plan: CompletePlan) {
        if (stack.size >= 30) stack.pollFirst()
        stack.addLast(plan)
    }

    private fun clearItineraryHistory() {
        itineraryUndo.clear()
        itineraryRedo.clear()
    }

    fun selectTab(tab: PlanTab) {
        val preferred = when (tab) {
            PlanTab.DAYS -> 0.58f
            PlanTab.STAYS -> 0.67f
            PlanTab.TRANSPORT -> 0.67f
            PlanTab.COSTS -> 0.62f
        }
        _state.update { it.copy(selectedTab = tab, panelFraction = preferred, autoCamera = true, focusedPlaceID = null) }
    }

    fun togglePanel() {
        _state.update { state ->
            state.copy(panelFraction = when {
                state.panelFraction < 0.30f -> 0.58f
                state.panelFraction < 0.76f -> 0.93f
                else -> 0.20f
            })
        }
    }

    fun resizePanel(fraction: Float) {
        _state.update { it.copy(panelFraction = fraction.coerceIn(0.18f, 0.94f)) }
    }

    fun resizePanelBy(deltaFraction: Float) {
        _state.update { it.copy(panelFraction = (it.panelFraction + deltaFraction).coerceIn(0.18f, 0.94f)) }
    }

    fun applyQuickAdjustment(request: String) {
        val text = request.trim()
        if (text.isEmpty()) return
        if (text in setOf("酒店", "看酒店", "打开酒店", "住宿", "看住宿")) {
            selectTab(PlanTab.STAYS)
            _state.update { it.copy(noticeMessage = "已把住处与当天价格铺开") }
            return
        }
        if (text in setOf("机票", "看机票", "航班", "火车", "高铁", "交通", "班次")) {
            selectTab(PlanTab.TRANSPORT)
            _state.update { it.copy(noticeMessage = "已把往返班次与价格铺开") }
            return
        }
        assistantJob?.cancel()
        assistantJob = viewModelScope.launch {
            val before = _state.value
            _state.update {
                it.copy(
                    isAssistantResponding = true,
                    errorMessage = null,
                    assistantStatusMessage = "正在听懂这句话…"
                )
            }
            val configuration = repository.assistantConfiguration()
            try {
                val interpretation = assistantClient.interpret(
                    input = text,
                    context = TravelAssistantContext.from(before.draft, before.plan, before.selectedDay),
                    configuration = configuration,
                    managedServiceURL = before.backendURL
                )
                applyAssistantActions(text, interpretation.actions, interpretation.reply)
            } catch (_: CancellationException) {
                return@launch
            } catch (error: Throwable) {
                val local = locallyAdjustedDraft(text, before.draft)
                if (local != before.draft) {
                    rebuildAfterAssistant(
                        draft = local,
                        reply = "云端的回声暂时没有抵达，这一步已由本机继续完成。"
                    )
                } else {
                    _state.update {
                        it.copy(
                            isAssistantResponding = false,
                            assistantStatusMessage = null,
                            errorMessage = error.message ?: "智能向导暂时没有回应"
                        )
                    }
                }
            }
        }
    }

    private suspend fun applyAssistantActions(
        rawText: String,
        actions: List<TravelAssistantAction>,
        reply: String
    ) {
        val before = _state.value
        var next = locallyAdjustedDraft(rawText, before.draft)
        var shouldRegenerate = next != before.draft
        var focusPlaceName: String? = null
        var removePlaceName: String? = null
        var maxNightlyPrice = before.accommodationMaxNightlyPrice
        var accommodationSort = before.accommodationSort

        actions.forEach { action ->
            when (action.type) {
                "set_destination" -> {
                    next = next.copy(destination = action.value)
                    shouldRegenerate = true
                }
                "set_origin" -> {
                    next = next.copy(origin = action.value)
                    shouldRegenerate = true
                }
                "set_pace" -> TripPace.entries.firstOrNull { it.name.equals(action.value, true) }?.let {
                    next = next.copy(pace = it)
                    shouldRegenerate = true
                }
                "set_travel_mode" -> LocalTravelMode.entries.firstOrNull { it.name.equals(action.value, true) }?.let {
                    next = next.copy(localTravelMode = it)
                    shouldRegenerate = true
                }
                "set_long_distance_mode" -> {
                    val mode = LongDistanceMode.entries.firstOrNull { it.name.equals(action.value, true) }
                    next = next.copy(preferredLongDistanceMode = if (action.value == "auto") null else mode)
                    shouldRegenerate = true
                }
                "set_skip_accommodation" -> {
                    next = next.copy(skipAccommodation = action.value.equals("true", true))
                    shouldRegenerate = true
                }
                "set_skip_transport" -> {
                    next = next.copy(skipTransport = action.value.equals("true", true))
                    shouldRegenerate = true
                }
                "set_day_count" -> action.value.toIntOrNull()?.let {
                    next = next.copy(dayCount = it.coerceIn(1, 7))
                    shouldRegenerate = true
                }
                "set_travelers" -> action.value.toIntOrNull()?.let {
                    next = next.copy(travelers = it.coerceIn(1, 8))
                    shouldRegenerate = true
                }
                "set_budget" -> action.value.toIntOrNull()?.let {
                    next = next.copy(budgetPerPerson = it.coerceIn(1_000, 30_000))
                    shouldRegenerate = true
                }
                "set_start_date" -> runCatching { LocalDate.parse(action.value) }.getOrNull()?.let {
                    next = next.copy(startDate = it.toString())
                    shouldRegenerate = true
                }
                "set_end_date" -> runCatching { LocalDate.parse(action.value) }.getOrNull()?.let { end ->
                    val start = runCatching { LocalDate.parse(next.startDate) }.getOrNull()
                    if (start != null && !end.isBefore(start)) {
                        next = next.copy(dayCount = (ChronoUnit.DAYS.between(start, end) + 1).toInt().coerceIn(1, 7))
                        shouldRegenerate = true
                    }
                }
                "set_accommodation_max_price" -> action.value.toIntOrNull()?.let {
                    maxNightlyPrice = it.coerceIn(100, 10_000)
                }
                "set_accommodation_sort" -> {
                    accommodationSort = when (action.value) {
                        "lowestPrice" -> AccommodationSort.LOWEST_PRICE
                        "closestToAttractions" -> AccommodationSort.CLOSEST_TO_ATTRACTIONS
                        "closestToTransit" -> AccommodationSort.CLOSEST_TO_TRANSIT
                        else -> AccommodationSort.RECOMMENDED
                    }
                }
                "add_interest" -> interest(action.value)?.let {
                    next = next.copy(interests = next.interests + it)
                    shouldRegenerate = true
                }
                "remove_interest" -> interest(action.value)?.let {
                    if (next.interests.size > 1) next = next.copy(interests = next.interests - it)
                    shouldRegenerate = true
                }
                "generate_plan" -> if (action.value.equals("true", true)) shouldRegenerate = true
                "focus_place" -> focusPlaceName = action.value
                "remove_place" -> removePlaceName = action.value
            }
        }

        repository.saveDraft(next)
        _state.update {
            it.copy(
                draft = next,
                accommodationMaxNightlyPrice = maxNightlyPrice,
                accommodationSort = accommodationSort
            )
        }
        if (shouldRegenerate) {
            rebuildAfterAssistant(next, reply, removePlaceName, focusPlaceName)
        } else {
            updatePlanPlaces(removePlaceName, focusPlaceName, reply)
        }
    }

    private fun locallyAdjustedDraft(text: String, initial: TripDraft): TripDraft {
        var next = initial
        Regex("(\\d{1,2})\\s*天").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let {
            next = next.copy(dayCount = it.coerceIn(1, 7))
        }
        Regex("(\\d{1,2})\\s*(?:人|位)").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let {
            next = next.copy(travelers = it.coerceIn(1, 8))
        }
        Regex("(?:预算|每人)?\\s*(\\d{3,6})\\s*(?:元|块)").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let {
            next = next.copy(budgetPerPerson = it.coerceIn(1_000, 30_000))
        }
        val destination = Regex("(?:去|前往|到)([\\p{IsHan}]{2,8})(?:玩|旅游|旅行|[，,。\\s]|$)")
            .find(text)?.groupValues?.getOrNull(1)
        if (!destination.isNullOrBlank()) next = next.copy(destination = destination)
        next = when {
            listOf("松弛", "轻松", "慢一点", "少一点").any(text::contains) -> next.copy(pace = TripPace.RELAXED)
            listOf("充实", "紧凑", "多安排", "赶一点").any(text::contains) -> next.copy(pace = TripPace.FULL)
            text.contains("适中") -> next.copy(pace = TripPace.BALANCED)
            else -> next
        }
        next = when {
            listOf("高铁", "火车", "动车").any(text::contains) -> next.copy(preferredLongDistanceMode = LongDistanceMode.TRAIN)
            listOf("飞机", "航班", "机票").any(text::contains) -> next.copy(preferredLongDistanceMode = LongDistanceMode.FLIGHT)
            text.contains("自驾") -> next.copy(preferredLongDistanceMode = LongDistanceMode.DRIVING)
            else -> next
        }
        if (listOf("不要住宿", "不住酒店", "跳过住宿").any(text::contains)) next = next.copy(skipAccommodation = true)
        if (listOf("需要住宿", "安排住宿", "要住酒店").any(text::contains)) next = next.copy(skipAccommodation = false)
        if (listOf("不要大交通", "跳过交通", "不安排交通", "不用查车票", "不用查机票").any(text::contains)) next = next.copy(skipTransport = true)
        if (listOf("安排交通", "需要交通", "查车票", "查机票").any(text::contains)) next = next.copy(skipTransport = false)
        return next
    }

    private suspend fun rebuildAfterAssistant(
        draft: TripDraft,
        reply: String,
        removePlaceName: String? = null,
        focusPlaceName: String? = null
    ) {
        try {
            val pack = resolver.resolve(draft)
            val previous = _state.value.plan
            val selectedNames = previous?.days.orEmpty().flatMap { it.stops }
                .filter { it.id in previous?.selectedPlaceIDs.orEmpty() }
                .mapTo(mutableSetOf()) { it.name }
            val selectedIDs = pack.places.filter { it.name in selectedNames }.mapTo(mutableSetOf()) { it.id }
            var plan = builder.build(draft, pack, selectedIDs, selectedIDs.isEmpty())
            if (!removePlaceName.isNullOrBlank()) plan = removingPlace(plan, removePlaceName)
            val focus = focusPlaceName?.let { name -> plan.days.flatMap { it.stops }.firstOrNull { it.name == name } }
            val day = focus?.let { place -> plan.days.firstOrNull { route -> route.stops.any { it.id == place.id } } }
            _state.update {
                it.copy(
                    plan = plan,
                    selectedDay = day?.index ?: it.selectedDay.coerceIn(0, (plan.days.size - 1).coerceAtLeast(0)),
                    selectedTab = PlanTab.DAYS,
                    panelFraction = 0.58f,
                    autoCamera = true,
                    focusedPlaceID = focus?.id,
                    isAssistantResponding = false,
                    assistantStatusMessage = null,
                    noticeMessage = reply,
                    errorMessage = null
                )
            }
            startPricingRefresh(plan)
            startRouteRefresh(plan)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            _state.update {
                it.copy(
                    isAssistantResponding = false,
                    assistantStatusMessage = null,
                    errorMessage = error.message ?: "这句话已经听懂，但地图暂时没能重新展开"
                )
            }
        }
    }

    private fun updatePlanPlaces(removePlaceName: String?, focusPlaceName: String?, reply: String) {
        val originalPlan = _state.value.plan
        var plan = originalPlan
        if (plan != null && !removePlaceName.isNullOrBlank()) plan = removingPlace(plan, removePlaceName)
        val focus = focusPlaceName?.let { name -> plan?.days.orEmpty().flatMap { it.stops }.firstOrNull { it.name == name } }
        val day = focus?.let { place -> plan?.days?.firstOrNull { route -> route.stops.any { it.id == place.id } } }
        _state.update {
            it.copy(
                plan = plan,
                selectedDay = day?.index ?: it.selectedDay,
                selectedTab = if (it.accommodationMaxNightlyPrice != null || it.accommodationSort != AccommodationSort.RECOMMENDED) PlanTab.STAYS else it.selectedTab,
                panelFraction = 0.58f,
                autoCamera = true,
                focusedPlaceID = focus?.id,
                isAssistantResponding = false,
                assistantStatusMessage = null,
                noticeMessage = reply
            )
        }
        if (plan != null && plan != originalPlan) startRouteRefresh(plan)
    }

    private fun removingPlace(plan: CompletePlan, name: String): CompletePlan {
        val match = plan.days.flatMap { it.stops }.firstOrNull { it.name == name } ?: return plan
        if (plan.days.sumOf { it.stops.size } <= 1) return plan
        return plan.copy(
            days = plan.days.map { day ->
                day.copy(
                    stops = day.stops.filterNot { it.id == match.id },
                    schedule = day.schedule.filterNot { it.placeId == match.id }
                )
            },
            selectedPlaceIDs = plan.selectedPlaceIDs - match.id,
            planningNotes = plan.planningNotes + "已按你的话移去$name，其余路线保持原来的节奏。"
        )
    }

    private fun interest(value: String): TripInterest? = when (value) {
        "gardens" -> TripInterest.GARDENS
        "culture" -> TripInterest.CULTURE
        "food" -> TripInterest.FOOD
        "nature" -> TripInterest.NATURE
        "family" -> TripInterest.FAMILY
        "night" -> TripInterest.NIGHT
        else -> null
    }

    private fun normalizedPlaceName(value: String): String = value
        .trim().lowercase().replace("（", "(").replace("）", ")").replace(" ", "")

    fun userMovedMap() {
        _state.update { it.copy(autoCamera = false) }
    }

    fun resumeAutoCamera() {
        _state.update {
            it.copy(
                autoCamera = true,
                cameraRequestToken = it.cameraRequestToken + 1,
                noticeMessage = "地图已回到当前路线"
            )
        }
    }

    fun cycleMapAppearance() {
        _state.update { state ->
            val values = MapAppearance.entries
            val next = values[(state.mapAppearance.ordinal + 1) % values.size]
            state.copy(mapAppearance = next, noticeMessage = "地图已换成${next.title}样式")
        }
    }

    fun orientMapNorth() {
        _state.update {
            it.copy(
                northRequestToken = it.northRequestToken + 1,
                noticeMessage = "地图已回到北向"
            )
        }
    }

    fun selectAccommodation(id: String) {
        val plan = _state.value.plan ?: return
        manuallySelectedAccommodationId = id
        _state.update {
            it.copy(
                plan = builder.selectAccommodation(plan, id),
                selectedTab = PlanTab.STAYS,
                panelFraction = 0.67f,
                autoCamera = true,
                noticeMessage = "住处改变了，接驳距离与交通排序也已更新"
            )
        }
    }

    fun selectTransport(id: String) {
        val plan = _state.value.plan ?: return
        manuallySelectedTransportId = id
        _state.update {
            it.copy(
                plan = builder.selectTransport(plan, id),
                selectedTab = PlanTab.TRANSPORT,
                panelFraction = 0.67f,
                autoCamera = true,
                noticeMessage = "已按这段抵达方式保留预算与接驳时间"
            )
        }
    }

    fun refreshLiveData() {
        _state.value.plan?.let(::startPricingRefresh)
    }

    fun setAccommodationPriceCeiling(value: Int?) {
        _state.update {
            it.copy(
                accommodationMaxNightlyPrice = value,
                selectedTab = PlanTab.STAYS,
                panelFraction = 0.67f,
                autoCamera = true,
                focusedPlaceID = null
            )
        }
    }

    fun setAccommodationSort(value: AccommodationSort) {
        _state.update {
            it.copy(
                accommodationSort = value,
                selectedTab = PlanTab.STAYS,
                panelFraction = 0.67f,
                autoCamera = true,
                focusedPlaceID = null
            )
        }
    }

    fun setAccommodationMinimumRating(value: Double?) {
        _state.update {
            it.copy(
                accommodationMinimumRating = value,
                selectedTab = PlanTab.STAYS,
                panelFraction = 0.67f
            )
        }
    }

    fun setAccommodationMaximumDistance(value: Int?) {
        _state.update {
            it.copy(
                accommodationMaximumAttractionDistanceMeters = value,
                selectedTab = PlanTab.STAYS,
                panelFraction = 0.67f,
                autoCamera = true
            )
        }
    }

    fun setAccommodationAmenity(value: AccommodationAmenity?) {
        _state.update {
            it.copy(
                accommodationAmenity = value,
                selectedTab = PlanTab.STAYS,
                panelFraction = 0.67f
            )
        }
    }

    private fun startPricingRefresh(basePlan: CompletePlan) {
        val token = ++pricingRefreshToken
        pricingRefreshJob?.cancel()
        val hubs = basePlan.transports.mapNotNull { it.arrivalAccessPoint }
            .distinctBy { "${it.kind}-${it.name}" }
        val operations = buildList<suspend () -> PricingRefreshResult> {
            add { directPricingClient.refresh(basePlan, hubs) }
            _state.value.backendURL.takeIf(String::isNotBlank)?.let { backendURL ->
                add { pricingClient.refresh(backendURL, basePlan, hubs) }
            }
        }
        _state.update { it.copy(isRefreshing = true, errorMessage = null, noticeMessage = "正在沿公开数据源寻找当日价格与班次…") }
        pricingRefreshJob = viewModelScope.launch {
            var successes = 0
            val failures = mutableListOf<String>()
            try {
                supervisorScope {
                    operations.forEach { operation ->
                        launch {
                            val outcome = try {
                                Result.success(operation())
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Throwable) {
                                Result.failure(error)
                            }
                            if (token != pricingRefreshToken) return@launch
                            outcome.onSuccess { result ->
                                successes += 1
                                _state.update { current ->
                                    val currentPlan = current.plan ?: return@update current
                                    var merged = builder.mergeLiveData(
                                        currentPlan,
                                        result.accommodationQuotes,
                                        result.transports,
                                        result.discoveredAccommodations
                                    )
                                    manuallySelectedAccommodationId
                                        ?.takeIf { id -> merged.accommodations.any { it.id == id } }
                                        ?.let { id -> merged = builder.selectAccommodation(merged, id) }
                                    manuallySelectedTransportId
                                        ?.takeIf { id -> merged.transports.any { it.id == id } }
                                        ?.let { id -> merged = builder.selectTransport(merged, id) }
                                    current.copy(
                                        plan = merged,
                                        noticeMessage = result.message,
                                        autoCamera = true
                                    )
                                }
                            }.onFailure { error ->
                                failures += (error.message ?: "一个价格源暂时没有回应")
                            }
                        }
                    }
                }
            } catch (_: CancellationException) {
                return@launch
            }
            if (token != pricingRefreshToken) return@launch
            _state.update { current ->
                when {
                    successes == 0 -> current.copy(
                        isRefreshing = false,
                        errorMessage = failures.firstOrNull() ?: "实时价格与班次暂时没有抵达"
                    )
                    failures.isNotEmpty() -> current.copy(
                        isRefreshing = false,
                        noticeMessage = listOfNotNull(current.noticeMessage, "另有一个补充渠道暂时未返回").joinToString("；")
                    )
                    else -> current.copy(isRefreshing = false)
                }
            }
        }
    }

    private fun startRouteRefresh(basePlan: CompletePlan) {
        val token = ++routeRefreshToken
        routeRefreshJob?.cancel()
        routeRefreshJob = viewModelScope.launch {
            try {
                val result = routeClient.routes(basePlan)
                if (token != routeRefreshToken) return@launch
                _state.update { current ->
                    val currentPlan = current.plan ?: return@update current
                    if (currentPlan.id != basePlan.id) return@update current
                    current.copy(
                        plan = currentPlan.copy(
                            routeSegments = result.segments,
                            failedRouteSegmentCount = result.failedSegmentCount,
                            routeIsSchematic = result.segments.isEmpty() || result.failedSegmentCount > 0
                        )
                    )
                }
            } catch (_: CancellationException) {
                return@launch
            } catch (_: Throwable) {
                if (token != routeRefreshToken) return@launch
                _state.update { current ->
                    val currentPlan = current.plan ?: return@update current
                    if (currentPlan.id != basePlan.id) return@update current
                    val expectedSegments = currentPlan.days.sumOf { (it.stops.size - 1).coerceAtLeast(0) }
                    current.copy(
                        plan = currentPlan.copy(
                            routeSegments = emptyList(),
                            failedRouteSegmentCount = expectedSegments,
                            routeIsSchematic = true
                        )
                    )
                }
            }
        }
    }

    fun saveCurrentPlan() {
        val plan = _state.value.plan ?: return
        runCatching { repository.savePlan(plan) }
            .onSuccess { saved ->
                _state.update { it.copy(savedPlans = saved, noticeMessage = "完整方案已经折进你的远方") }
            }
            .onFailure {
                _state.update {
                    it.copy(noticeMessage = "本机旅册没有写入成功。当前方案仍在，请先不要清理应用数据并稍后重试。")
                }
            }
    }

    fun loadPlan(plan: CompletePlan) {
        repository.saveDraft(plan.draft)
        clearItineraryHistory()
        _state.update {
            it.copy(
                draft = plan.draft,
                plan = plan,
                libraryVisible = false,
                selectedTab = PlanTab.DAYS,
                selectedDay = 0,
                canUndoItinerary = false,
                canRedoItinerary = false,
                panelFraction = 0.58f,
                autoCamera = true,
                noticeMessage = "已回到${plan.draft.destination}的路线"
            )
        }
        if (plan.routeSegments.isEmpty() || plan.routeIsSchematic) startRouteRefresh(plan)
        startPricingRefresh(plan)
    }

    fun deletePlan(id: String) {
        _state.update { it.copy(savedPlans = repository.deletePlan(id)) }
    }

    fun showSettings(show: Boolean) {
        _state.update { it.copy(settingsVisible = show, backendHealthy = null, assistantStatusMessage = null, errorMessage = null) }
    }

    fun showLibrary(show: Boolean) {
        _state.update { it.copy(libraryVisible = show, errorMessage = null) }
    }

    fun saveBackendURL(value: String) {
        repository.saveBackendURL(value)
        _state.update { it.copy(backendURL = repository.backendURL(), backendHealthy = null, noticeMessage = "服务偏好已保存在本机") }
    }

    fun testBackend(value: String) {
        viewModelScope.launch {
            _state.update { it.copy(backendHealthy = null, errorMessage = null) }
            val healthy = pricingClient.healthCheck(value)
            _state.update { it.copy(backendHealthy = healthy) }
        }
    }

    fun saveAssistantConfiguration(
        mode: AssistantProviderMode,
        customBaseURL: String,
        customModel: String,
        customAPIKey: String
    ) {
        runCatching {
            repository.saveAssistantConfiguration(mode, customBaseURL, customModel, customAPIKey)
        }.onSuccess { configuration ->
            _state.update {
                it.copy(
                    assistantMode = configuration.mode,
                    customAssistantBaseURL = configuration.customBaseURL,
                    customAssistantModel = configuration.customModel,
                    hasCustomAssistantAPIKey = configuration.hasCustomAPIKey,
                    assistantStatusMessage = "智能向导的选择已安全保存在本机",
                    errorMessage = null
                )
            }
        }.onFailure { error ->
            _state.update { it.copy(errorMessage = error.message ?: "暂时无法保存模型设置") }
        }
    }

    fun deleteAssistantAPIKey() {
        val configuration = repository.deleteAssistantAPIKey()
        _state.update {
            it.copy(
                hasCustomAssistantAPIKey = configuration.hasCustomAPIKey,
                assistantStatusMessage = "自定义 API Key 已从本机删除"
            )
        }
    }

    fun testAssistantConfiguration(
        mode: AssistantProviderMode,
        customBaseURL: String,
        customModel: String,
        customAPIKey: String
    ) {
        viewModelScope.launch {
            _state.update { it.copy(isAssistantResponding = true, assistantStatusMessage = "正在确认智能向导…", errorMessage = null) }
            val stored = repository.assistantConfiguration()
            val configuration = AssistantConfiguration(
                mode = mode,
                customBaseURL = customBaseURL.trim(),
                customModel = customModel.trim(),
                customAPIKey = customAPIKey.trim().ifBlank { stored.customAPIKey }
            )
            runCatching {
                assistantClient.interpret(
                    input = "只确认服务已经接通，不要修改行程。",
                    context = TravelAssistantContext.from(_state.value.draft, _state.value.plan, _state.value.selectedDay),
                    configuration = configuration,
                    managedServiceURL = _state.value.backendURL
                )
            }.onSuccess { result ->
                _state.update {
                    it.copy(
                        isAssistantResponding = false,
                        assistantStatusMessage = "已接通 ${result.model ?: configuration.customModel}：${result.reply}"
                    )
                }
            }.onFailure { error ->
                _state.update {
                    it.copy(
                        isAssistantResponding = false,
                        assistantStatusMessage = error.message ?: "智能向导暂时没有回应"
                    )
                }
            }
        }
    }

    fun dismissMessage() {
        _state.update { it.copy(errorMessage = null, noticeMessage = null) }
    }
}

class PlannerViewModelFactory(
    private val repository: AppRepository,
    private val resolver: DestinationResolver
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(PlannerViewModel::class.java)) {
            return PlannerViewModel(repository, resolver) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
    }
}
