package cn.anytravel.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import cn.anytravel.app.data.AppRepository
import cn.anytravel.app.data.PricingClient
import cn.anytravel.app.domain.DestinationResolver
import cn.anytravel.app.domain.PlanBuilder
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.TripDraft
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
    val panelExpanded: Boolean = false,
    val autoCamera: Boolean = true,
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    val settingsVisible: Boolean = false,
    val libraryVisible: Boolean = false,
    val errorMessage: String? = null,
    val noticeMessage: String? = null,
    val backendHealthy: Boolean? = null
)

class PlannerViewModel(
    private val repository: AppRepository,
    private val resolver: DestinationResolver,
    private val builder: PlanBuilder = PlanBuilder(),
    private val pricingClient: PricingClient = PricingClient()
) : ViewModel() {
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
                val pack = resolver.resolve(draft)
                builder.build(draft, pack)
            }.onSuccess { plan ->
                _state.update {
                    it.copy(
                        plan = plan,
                        isLoading = false,
                        selectedTab = PlanTab.DAYS,
                        selectedDay = 0,
                        panelExpanded = false,
                        noticeMessage = "路线、住处与抵达方式已经在地图上展开"
                    )
                }
            }.onFailure { error ->
                _state.update { it.copy(isLoading = false, errorMessage = error.message ?: "暂时无法生成路线，请稍后重试") }
            }
        }
    }

    fun returnToDraft() {
        _state.update { it.copy(plan = null, panelExpanded = false, errorMessage = null, noticeMessage = null) }
    }

    fun selectDay(index: Int) {
        _state.update { it.copy(selectedDay = index, selectedTab = PlanTab.DAYS, autoCamera = true) }
    }

    fun selectTab(tab: PlanTab) {
        _state.update { it.copy(selectedTab = tab, panelExpanded = true, autoCamera = true) }
    }

    fun togglePanel() {
        _state.update { it.copy(panelExpanded = !it.panelExpanded) }
    }

    fun userMovedMap() {
        _state.update { it.copy(autoCamera = false) }
    }

    fun resumeAutoCamera() {
        _state.update { it.copy(autoCamera = true) }
    }

    fun selectAccommodation(id: String) {
        val plan = _state.value.plan ?: return
        _state.update {
            it.copy(
                plan = builder.selectAccommodation(plan, id),
                selectedTab = PlanTab.STAYS,
                autoCamera = true,
                noticeMessage = "住处改变了，接驳距离与交通排序也已更新"
            )
        }
    }

    fun selectTransport(id: String) {
        val plan = _state.value.plan ?: return
        _state.update {
            it.copy(
                plan = builder.selectTransport(plan, id),
                selectedTab = PlanTab.TRANSPORT,
                autoCamera = true,
                noticeMessage = "已按这段抵达方式保留预算与接驳时间"
            )
        }
    }

    fun refreshLiveData() {
        val current = _state.value
        val plan = current.plan ?: return
        if (current.backendURL.isBlank()) {
            _state.update { it.copy(settingsVisible = true, errorMessage = "先填写你自己的开源报价节点地址") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isRefreshing = true, errorMessage = null, noticeMessage = null) }
            runCatching {
                val hubs = plan.transports.mapNotNull { it.arrivalAccessPoint }.distinctBy { "${it.kind}-${it.name}" }
                pricingClient.refresh(current.backendURL, plan.draft, plan.accommodations, hubs)
            }.onSuccess { result ->
                _state.update {
                    it.copy(
                        plan = builder.mergeLiveData(plan, result.accommodationQuotes, result.transports),
                        isRefreshing = false,
                        noticeMessage = result.message,
                        autoCamera = true
                    )
                }
            }.onFailure { error ->
                _state.update { it.copy(isRefreshing = false, errorMessage = error.message ?: "报价节点暂时没有回应") }
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
