package cn.anytravel.app.data

import cn.anytravel.app.BuildConfig
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.TripDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.time.LocalDate

enum class AssistantProviderMode(val title: String) {
    MANAGED("AnyTravel 智能服务"),
    CUSTOM("自定义服务")
}

data class AssistantConfiguration(
    val mode: AssistantProviderMode = AssistantProviderMode.MANAGED,
    val customBaseURL: String = "https://open.bigmodel.cn/api/paas/v4",
    val customModel: String = "glm-5.3-flash",
    val customAPIKey: String? = null
) {
    val hasCustomAPIKey: Boolean get() = !customAPIKey.isNullOrBlank()
}

@Serializable
data class TravelAssistantPlaceContext(
    val name: String,
    val dayIndex: Int,
    val interest: String
)

@Serializable
data class TravelAssistantContext(
    val destination: String,
    val dayCount: Int,
    val budgetPerPerson: Int,
    val pace: String,
    val travelMode: String,
    val selectedDayIndex: Int,
    val interests: List<String>,
    val places: List<TravelAssistantPlaceContext>,
    val origin: String,
    val travelers: Int,
    val startDate: String?,
    val endDate: String?,
    val longDistanceMode: String?,
    val skipAccommodation: Boolean,
    val skipTransport: Boolean,
    val accommodationMaxNightlyPrice: Int? = null,
    val accommodationSort: String = "recommended"
) {
    companion object {
        fun from(draft: TripDraft, plan: CompletePlan?, selectedDayIndex: Int): TravelAssistantContext {
            val places = plan?.days.orEmpty().flatMap { day ->
                day.stops.map { place ->
                    TravelAssistantPlaceContext(
                        name = place.name,
                        dayIndex = day.index,
                        interest = place.interest.name.lowercase()
                    )
                }
            }
            val start = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
            return TravelAssistantContext(
                destination = draft.destination,
                dayCount = draft.dayCount.coerceIn(1, 7),
                budgetPerPerson = draft.budgetPerPerson.coerceIn(1_000, 30_000),
                pace = draft.pace.name.lowercase(),
                travelMode = draft.localTravelMode.name.lowercase(),
                selectedDayIndex = selectedDayIndex.coerceIn(0, 6),
                interests = draft.interests.map { it.name.lowercase() }.sorted(),
                places = places.take(80),
                origin = draft.origin,
                travelers = draft.travelers.coerceIn(1, 8),
                startDate = start?.toString(),
                endDate = start?.plusDays((draft.dayCount - 1).coerceAtLeast(0).toLong())?.toString(),
                longDistanceMode = draft.preferredLongDistanceMode?.name?.lowercase(),
                skipAccommodation = draft.skipAccommodation,
                skipTransport = draft.skipTransport
            )
        }
    }
}

@Serializable
data class TravelAssistantAction(val type: String, val value: String)

@Serializable
data class TravelAssistantInterpretation(
    val reply: String,
    val actions: List<TravelAssistantAction> = emptyList(),
    val model: String? = null,
    val capturedAt: String? = null
)

@Serializable
private data class TravelAssistantRequest(val input: String, val context: TravelAssistantContext)

@Serializable
private data class OpenAIChatRequest(
    val model: String,
    val temperature: Double,
    @SerialName("response_format") val responseFormat: ResponseFormat,
    val messages: List<Message>
) {
    @Serializable data class ResponseFormat(val type: String)
    @Serializable data class Message(val role: String, val content: String)
}

@Serializable
private data class OpenAIChatResponse(val choices: List<Choice> = emptyList()) {
    @Serializable data class Choice(val message: Message)
    @Serializable data class Message(val content: String)
}

@Serializable
private data class AssistantBackendError(val error: String? = null, val message: String? = null)

class TravelAssistantClient {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    suspend fun interpret(
        input: String,
        context: TravelAssistantContext,
        configuration: AssistantConfiguration,
        managedServiceURL: String
    ): TravelAssistantInterpretation {
        val cleanInput = input.trim().take(1_000)
        if (cleanInput.isBlank()) throw AssistantException("先说出你想改变的旅程。")
        val payload = TravelAssistantRequest(cleanInput, context)
        val raw = when (configuration.mode) {
            AssistantProviderMode.MANAGED -> {
                if (managedServiceURL.isNotBlank()) {
                    val endpoint = endpoint(managedServiceURL, "v1/assistant/interpret", allowLocalHTTP = true)
                    val body = post(endpoint, json.encodeToString(payload))
                    runCatching { json.decodeFromString<TravelAssistantInterpretation>(body) }
                        .getOrElse { throw AssistantException("智能向导返回了无法辨认的内容。") }
                } else {
                    val key = BuildConfig.ZAI_API_KEY.trim()
                    if (key.isBlank()) throw AssistantException("内置智能服务尚未配置。")
                    openAIInterpretation(
                        payload,
                        baseURL = "https://open.bigmodel.cn/api/paas/v4",
                        apiKey = key,
                        model = "glm-5.3-flash"
                    )
                }
            }
            AssistantProviderMode.CUSTOM -> {
                val key = configuration.customAPIKey?.trim().orEmpty()
                if (key.isBlank()) throw AssistantException("请先保存自己的 API Key。")
                val model = configuration.customModel.trim()
                if (model.isBlank()) throw AssistantException("请填写模型名称。")
                openAIInterpretation(payload, configuration.customBaseURL, key, model)
            }
        }
        return validate(raw, context.places)
    }

    private suspend fun openAIInterpretation(
        payload: TravelAssistantRequest,
        baseURL: String,
        apiKey: String,
        model: String
    ): TravelAssistantInterpretation {
        val request = OpenAIChatRequest(
            model = model,
            temperature = 0.1,
            responseFormat = OpenAIChatRequest.ResponseFormat("json_object"),
            messages = listOf(
                OpenAIChatRequest.Message("system", systemPrompt),
                OpenAIChatRequest.Message("user", json.encodeToString(payload))
            )
        )
        val body = post(
            endpoint(baseURL, "chat/completions", allowLocalHTTP = true),
            json.encodeToString(request),
            apiKey
        )
        val content = runCatching { json.decodeFromString<OpenAIChatResponse>(body) }
            .getOrNull()?.choices?.firstOrNull()?.message?.content
            ?: throw AssistantException("智能向导返回了无法辨认的内容。")
        val unfenced = content.trim()
            .removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
        val result = runCatching { json.decodeFromString<TravelAssistantInterpretation>(unfenced) }
            .getOrElse { throw AssistantException("智能向导没有返回约定的旅程动作。") }
        return result.copy(model = model)
    }

    private suspend fun post(url: URL, body: String, apiKey: String? = null): String = withContext(Dispatchers.IO) {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 45_000
            doOutput = true
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("User-Agent", "AnyTravel-Android/0.8.1 (+https://github.com/Rseam-07/AnyTravel)")
            if (!apiKey.isNullOrBlank()) setRequestProperty("Authorization", "Bearer $apiKey")
        }
        try {
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                val detail = runCatching { json.decodeFromString<AssistantBackendError>(response) }.getOrNull()
                throw AssistantException(detail?.message ?: detail?.error ?: "智能服务返回 HTTP $status")
            }
            response
        } catch (error: AssistantException) {
            throw error
        } catch (error: Exception) {
            throw AssistantException("智能向导暂时走散了：${error.message ?: "网络没有回应"}")
        } finally {
            connection.disconnect()
        }
    }

    private fun endpoint(baseURL: String, path: String, allowLocalHTTP: Boolean): URL {
        val uri = runCatching { URI(baseURL.trim()) }.getOrNull()
            ?: throw AssistantException("模型服务地址无法识别。")
        val local = uri.host in setOf("localhost", "127.0.0.1", "::1")
        val validScheme = uri.scheme == "https" || (allowLocalHTTP && local && uri.scheme == "http")
        if (!validScheme || uri.host.isNullOrBlank()) {
            throw AssistantException("模型服务请使用 HTTPS，或本机调试地址。")
        }
        return URL(baseURL.trim().trimEnd('/') + "/" + path.trimStart('/'))
    }

    internal fun validate(
        result: TravelAssistantInterpretation,
        places: List<TravelAssistantPlaceContext>
    ): TravelAssistantInterpretation {
        val canonicalPlaces = places.associateBy { normalizeName(it.name) }
        val actions = result.actions.take(16).mapNotNull { action ->
            val value = action.value.trim()
            when (action.type) {
                "set_destination", "set_origin" -> value.takeIf(String::isNotBlank)?.take(80)
                "set_pace" -> value.takeIf { it in setOf("relaxed", "balanced", "full") }
                "set_travel_mode" -> value.takeIf { it in setOf("walking", "transit", "driving") }
                "set_long_distance_mode" -> value.takeIf { it in setOf("auto", "train", "flight", "driving", "coach") }
                "set_skip_accommodation", "set_skip_transport" -> value.lowercase().takeIf { it in setOf("true", "false") }
                "set_day_count" -> value.toIntOrNull()?.coerceIn(1, 7)?.toString()
                "set_travelers" -> value.toIntOrNull()?.coerceIn(1, 8)?.toString()
                "set_budget" -> value.toIntOrNull()?.coerceIn(1_000, 30_000)?.toString()
                "set_start_date", "set_end_date" -> value.takeIf(::validDay)
                "set_accommodation_max_price" -> value.toIntOrNull()?.coerceIn(100, 10_000)?.toString()
                "set_accommodation_sort" -> value.takeIf {
                    it in setOf("recommended", "lowestPrice", "closestToAttractions", "closestToTransit")
                }
                "add_interest", "remove_interest" -> value.takeIf {
                    it in setOf("gardens", "culture", "food", "nature", "family", "night")
                }
                "generate_plan" -> value.lowercase().takeIf { it in setOf("true", "false") }
                "focus_place", "remove_place" -> canonicalPlaces[normalizeName(value)]?.name
                else -> null
            }?.let { TravelAssistantAction(action.type, it) }
        }
        return result.copy(reply = result.reply.trim().take(600), actions = actions)
    }

    private fun normalizeName(value: String): String = value.trim().lowercase()
        .replace("（", "(").replace("）", ")").replace(" ", "")

    private fun validDay(value: String): Boolean = runCatching {
        LocalDate.parse(value).toString() == value
    }.getOrDefault(false)

    companion object {
        private val systemPrompt = """
            你是 AnyTravel 的旅行意图控制器。用户可以用完全自由的中文开始或修改旅行。只返回 JSON：
            {"reply":"简洁、温暖、略有诗意的中文回应","actions":[{"type":"动作","value":"值"}]}
            允许动作：set_destination、set_origin、set_day_count(1...7)、set_travelers(1...8)、set_budget(1000...30000)、set_pace(relaxed|balanced|full)、set_travel_mode(walking|transit|driving)、set_long_distance_mode(auto|train|flight|driving|coach)、set_skip_accommodation/set_skip_transport(true|false)、set_start_date/set_end_date(yyyy-MM-dd)、set_accommodation_max_price(100...10000)、set_accommodation_sort(recommended|lowestPrice|closestToAttractions|closestToTransit)、add_interest/remove_interest(gardens|culture|food|nature|family|night)、generate_plan(true|false)、focus_place/remove_place（地点名必须来自 context.places）。
            明确要求规划时返回 generate_plan=true。不要臆造地点，不要返回链接、代码或额外字段；无法安全执行时 actions 为空。回复不超过 120 个汉字。
        """.trimIndent()
    }
}

class AssistantException(message: String) : Exception(message)
