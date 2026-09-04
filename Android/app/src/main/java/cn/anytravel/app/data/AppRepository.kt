package cn.anytravel.app.data

import android.content.Context
import androidx.core.content.edit
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.TripDraft
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

class AppRepository(context: Context) {
    private val preferences = context.getSharedPreferences("anytravel", Context.MODE_PRIVATE)
    private val assistantSecrets = AssistantSecretStore(context)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun isOnboardingComplete(): Boolean = preferences.getBoolean(KEY_ONBOARDING, false)

    fun completeOnboarding(origin: String, budgetPerPerson: Int, travelers: Int) {
        val draft = loadDraft().copy(
            origin = origin.trim().ifBlank { "上海" },
            budgetPerPerson = budgetPerPerson.coerceIn(800, 30_000),
            travelers = travelers.coerceIn(1, 8)
        )
        preferences.edit {
            putBoolean(KEY_ONBOARDING, true)
            putString(KEY_DRAFT, json.encodeToString(TripDraft.serializer(), draft))
        }
    }

    fun skipOnboarding() {
        preferences.edit { putBoolean(KEY_ONBOARDING, true) }
    }

    fun resetOnboarding() {
        preferences.edit { putBoolean(KEY_ONBOARDING, false) }
    }

    fun loadDraft(): TripDraft = preferences.getString(KEY_DRAFT, null)?.let { encoded ->
        runCatching { json.decodeFromString(TripDraft.serializer(), encoded) }.getOrNull()
    } ?: TripDraft()

    fun saveDraft(draft: TripDraft) {
        preferences.edit { putString(KEY_DRAFT, json.encodeToString(TripDraft.serializer(), draft)) }
    }

    fun loadPlans(): List<CompletePlan> = preferences.getString(KEY_PLANS, null)?.let { encoded ->
        runCatching { json.decodeFromString(ListSerializer(CompletePlan.serializer()), encoded) }.getOrNull()
    }.orEmpty()

    fun savePlan(plan: CompletePlan): List<CompletePlan> {
        val updated = (listOf(plan) + loadPlans().filterNot { it.id == plan.id }).take(12)
        writePlans(updated)
        return updated
    }

    fun deletePlan(id: String): List<CompletePlan> {
        val updated = loadPlans().filterNot { it.id == id }
        writePlans(updated)
        return updated
    }

    fun backendURL(): String = preferences.getString(KEY_BACKEND_URL, "").orEmpty()

    fun saveBackendURL(value: String) {
        preferences.edit { putString(KEY_BACKEND_URL, value.trim()) }
    }

    fun assistantConfiguration(): AssistantConfiguration = AssistantConfiguration(
        mode = preferences.getString(KEY_ASSISTANT_MODE, null)
            ?.let { runCatching { AssistantProviderMode.valueOf(it) }.getOrNull() }
            ?: AssistantProviderMode.MANAGED,
        customBaseURL = preferences.getString(KEY_ASSISTANT_BASE_URL, null)
            ?: "https://open.bigmodel.cn/api/paas/v4",
        customModel = preferences.getString(KEY_ASSISTANT_MODEL, null) ?: "glm-5.3-flash",
        customAPIKey = assistantSecrets.read()
    )

    fun saveAssistantConfiguration(
        mode: AssistantProviderMode,
        customBaseURL: String,
        customModel: String,
        customAPIKey: String?
    ): AssistantConfiguration {
        preferences.edit {
            putString(KEY_ASSISTANT_MODE, mode.name)
            putString(KEY_ASSISTANT_BASE_URL, customBaseURL.trim())
            putString(KEY_ASSISTANT_MODEL, customModel.trim())
        }
        customAPIKey?.trim()?.takeIf(String::isNotBlank)?.let(assistantSecrets::save)
        return assistantConfiguration()
    }

    fun deleteAssistantAPIKey(): AssistantConfiguration {
        assistantSecrets.delete()
        return assistantConfiguration()
    }

    private fun writePlans(plans: List<CompletePlan>) {
        preferences.edit { putString(KEY_PLANS, json.encodeToString(ListSerializer(CompletePlan.serializer()), plans)) }
    }

    companion object {
        private const val KEY_ONBOARDING = "onboarding_complete"
        private const val KEY_DRAFT = "trip_draft"
        private const val KEY_PLANS = "saved_plans"
        private const val KEY_BACKEND_URL = "pricing_backend_url"
        private const val KEY_ASSISTANT_MODE = "assistant_provider_mode"
        private const val KEY_ASSISTANT_BASE_URL = "assistant_custom_base_url"
        private const val KEY_ASSISTANT_MODEL = "assistant_custom_model"
    }
}
