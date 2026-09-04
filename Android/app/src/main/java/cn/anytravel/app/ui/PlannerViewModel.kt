package cn.anytravel.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import cn.anytravel.app.data.AppRepository
import cn.anytravel.app.data.DirectPricingClient
import cn.anytravel.app.data.PricingClient
import cn.anytravel.app.data.PricingRefreshResult
import cn.anytravel.app.domain.DestinationResolver
import cn.anytravel.app.domain.PlanBuilder
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.TripPace
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class PlanTab(val title: String) {
    DAYS("日程"),
    STAYS("住宿"),
    TRANSPORT("交通"),
    COSTS("费用")
}

data class PlannerUiState(
    val onboardingComplete: Boolean,
    val draft: TripDraft,
    val plan: CompletePlan? = null,
    val savedPlans: List<CompletePlan> = emptyList(),
    val backendURL: String = "",
    val selectedTab: PlanTab = PlanTab.DAYS,
    val selectedDay: Int = 0,
    val panelFraction: Float = 0.62f,
    val autoCamera: Boolean = true,
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
    private val directPricingClient: DirectPricingClient = DirectPricingClient()
) : ViewModel() {
    private var pricingRefreshToken = 0
    private var manuallySelectedAccommodationId: String? = null
    private var manuallySelectedTransportId: String? = null
    private val _state = MutableStateFlow(
        PlannerUiState(
            onboardingComplete = repository.isOnboardingComplete(),
            draft = repository.loadDraft(),
            savedPlans = repository.loadPlans(),
            backendURL = repository.backendURL()
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
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, errorMessage = null, noticeMessage = null, autoCamera = true) }
            runCatching {
                resolver.resolve(draft)
            }.onSuccess { pack ->
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
            }.onFailure { error ->
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

    private fun finishPlanning(selectionWasSkipped: Boolean) {
        val current = _state.value
        val pack = current.pendingDestinationPack ?: return
        val selected = if (selectionWasSkipped) emptySet() else current.selectedAttractionIDs
        val plan = builder.build(current.draft, pack, selected, selectionWasSkipped)
        manuallySelectedAccommodationId = null
        manuallySelectedTransportId = null
        _state.update {
            it.copy(
                plan = plan,
                attractionPickerVisible = false,
                pendingDestinationPack = null,
                selectedTab = PlanTab.DAYS,
                selectedDay = 0,
                panelFraction = 0.58f,
                noticeMessage = if (selectionWasSkipped) {
                    "已按热度、兴趣与距离补齐一条轻松路线"
                } else {
                    "已优先为你选中的${selected.size}处留出时间"
                }
            )
        }
        startPricingRefresh(plan)
    }

    fun returnToDraft() {
        pricingRefreshToken += 1
        manuallySelectedAccommodationId = null
        manuallySelectedTransportId = null
        _state.update { it.copy(plan = null, panelFraction = 0.62f, isRefreshing = false, errorMessage = null, noticeMessage = null) }
    }

    fun selectDay(index: Int) {
        _state.update { it.copy(selectedDay = index, selectedTab = PlanTab.DAYS, panelFraction = 0.58f, autoCamera = true) }
    }

    fun selectTab(tab: PlanTab) {
        val preferred = when (tab) {
            PlanTab.DAYS -> 0.58f
            PlanTab.STAYS -> 0.67f
            PlanTab.TRANSPORT -> 0.67f
            PlanTab.COSTS -> 0.62f
        }
        _state.update { it.copy(selectedTab = tab, panelFraction = preferred, autoCamera = true) }
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
        val onlyNavigation = text.none(Char::isDigit)
        if (onlyNavigation && listOf("酒店", "住宿", "民宿").any(text::contains)) {
            selectTab(PlanTab.STAYS)
            _state.update { it.copy(noticeMessage = "已把住处与当天价格铺开") }
            return
        }
        if (onlyNavigation && listOf("机票", "航班", "火车", "高铁", "交通", "班次").any(text::contains)) {
            selectTab(PlanTab.TRANSPORT)
            _state.update { it.copy(noticeMessage = "已把往返班次与价格铺开") }
            return
        }
        var next = _state.value.draft
        Regex("(\\d{1,2})\\s*天").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let {
            next = next.copy(dayCount = it.coerceIn(1, 14))
        }
        Regex("(\\d{1,2})\\s*(?:人|位)").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let {
            next = next.copy(travelers = it.coerceIn(1, 12))
        }
        Regex("(?:预算|每人)?\\s*(\\d{3,6})\\s*(?:元|块)").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let {
            next = next.copy(budgetPerPerson = it.coerceIn(500, 100_000))
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
        repository.saveDraft(next)
        _state.update { it.copy(draft = next, panelFraction = 0.58f, noticeMessage = "正在按这句话重新展开旅程") }
        generatePlan()
    }

    fun userMovedMap() {
        _state.update { it.copy(autoCamera = false) }
    }

    fun resumeAutoCamera() {
        _state.update { it.copy(autoCamera = true) }
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

    private fun startPricingRefresh(basePlan: CompletePlan) {
        val token = ++pricingRefreshToken
        val hubs = basePlan.transports.mapNotNull { it.arrivalAccessPoint }
            .distinctBy { "${it.kind}-${it.name}" }
        val operations = buildList<suspend () -> PricingRefreshResult> {
            add { directPricingClient.refresh(basePlan, hubs) }
            _state.value.backendURL.takeIf(String::isNotBlank)?.let { backendURL ->
                add { pricingClient.refresh(backendURL, basePlan.draft, basePlan.accommodations, hubs) }
            }
        }
        var remaining = operations.size
        var successes = 0
        val failures = mutableListOf<String>()
        _state.update { it.copy(isRefreshing = true, errorMessage = null, noticeMessage = "正在沿公开数据源寻找当日价格与班次…") }
        operations.forEach { operation ->
            viewModelScope.launch {
                val outcome = runCatching { operation() }
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
                        manuallySelectedAccommodationId?.takeIf { id -> merged.accommodations.any { it.id == id } }?.let { id ->
                            merged = builder.selectAccommodation(merged, id)
                        }
                        manuallySelectedTransportId?.takeIf { id -> merged.transports.any { it.id == id } }?.let { id ->
                            merged = builder.selectTransport(merged, id)
                        }
                        current.copy(
                            plan = merged,
                            noticeMessage = result.message,
                            autoCamera = true
                        )
                    }
                }.onFailure { error ->
                    failures += (error.message ?: "一个价格源暂时没有回应")
                }
                remaining -= 1
                if (remaining == 0) {
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
        }
    }

    fun saveCurrentPlan() {
        val plan = _state.value.plan ?: return
        val saved = repository.savePlan(plan)
        _state.update { it.copy(savedPlans = saved, noticeMessage = "这段旅程已经折进你的远方") }
    }

    fun loadPlan(plan: CompletePlan) {
        repository.saveDraft(plan.draft)
        _state.update {
            it.copy(
                draft = plan.draft,
                plan = plan,
                libraryVisible = false,
                selectedTab = PlanTab.DAYS,
                selectedDay = 0,
                panelFraction = 0.58f,
                autoCamera = true,
                noticeMessage = "已回到${plan.draft.destination}的路线"
            )
        }
    }

    fun deletePlan(id: String) {
        _state.update { it.copy(savedPlans = repository.deletePlan(id)) }
    }

    fun showSettings(show: Boolean) {
        _state.update { it.copy(settingsVisible = show, backendHealthy = null, errorMessage = null) }
    }

    fun showLibrary(show: Boolean) {
        _state.update { it.copy(libraryVisible = show, errorMessage = null) }
    }

    fun saveBackendURL(value: String) {
        repository.saveBackendURL(value)
        _state.update { it.copy(backendURL = value.trim(), backendHealthy = null, noticeMessage = "报价节点地址已保存在本机") }
    }

    fun testBackend(value: String) {
        viewModelScope.launch {
            _state.update { it.copy(backendHealthy = null, errorMessage = null) }
            val healthy = pricingClient.healthCheck(value)
            _state.update { it.copy(backendHealthy = healthy) }
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
