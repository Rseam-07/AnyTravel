package cn.anytravel.app.data

import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.TransportOption
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.distanceText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

class PricingClient {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    suspend fun refresh(
        baseURL: String,
        draft: TripDraft,
        accommodations: List<AccommodationOption>,
        accessPoints: List<AccessPoint>
    ): PricingRefreshResult = coroutineScope {
        val normalized = normalizeBaseURL(baseURL)
        val hotelRequest = async {
            if (accommodations.isEmpty()) emptyMap() else fetchAccommodationQuotes(normalized, draft, accommodations)
        }
        val transportRequest = async { fetchTransportOptions(normalized, draft, accessPoints, accommodations.firstOrNull()) }
        val hotelResult = runCatching { hotelRequest.await() }
        val transportResult = runCatching { transportRequest.await() }
        val failures = listOfNotNull(
            hotelResult.exceptionOrNull()?.message?.let { "住宿：$it" },
            transportResult.exceptionOrNull()?.message?.let { "交通：$it" }
        )
        PricingRefreshResult(
            accommodationQuotes = hotelResult.getOrDefault(emptyMap()),
            transports = transportResult.getOrDefault(emptyList()),
            message = when {
                failures.size == 2 -> throw PricingException(failures.joinToString("；"))
                failures.isNotEmpty() -> "部分渠道没有返回：${failures.joinToString("；")}"
                else -> "价格与班次已按当前日期刷新"
            }
        )
    }

    suspend fun healthCheck(baseURL: String): Boolean = runCatching {
        val normalized = normalizeBaseURL(baseURL)
        request(URL(normalized, "health"), "GET", null).isNotBlank()
    }.getOrDefault(false)

    private suspend fun fetchAccommodationQuotes(
        baseURL: URL,
        draft: TripDraft,
        accommodations: List<AccommodationOption>
    ): Map<String, List<PriceQuote>> {
        val start = LocalDate.parse(draft.startDate)
        val payload = AccommodationRequest(
            destination = draft.destination,
            checkIn = start.toString(),
            checkOut = start.plusDays(draft.nights.toLong().coerceAtLeast(1)).toString(),
            adults = draft.travelers,
            rooms = ((draft.travelers + 1) / 2).coerceAtLeast(1),
            hotels = accommodations.map { HotelRequest(it.id, it.name, it.coordinate.latitude, it.coordinate.longitude) }
        )
        val response = json.decodeFromString<AccommodationResponse>(
            request(URL(baseURL, "v1/quotes/accommodations"), "POST", json.encodeToString(payload))
        )
        return response.quotes.mapNotNull { quote ->
            val option = accommodations.firstOrNull { it.id == quote.hotelID }
                ?: accommodations.firstOrNull { normalizedName(it.name) == normalizedName(quote.hotelName) }
                ?: return@mapNotNull null
            option.id to PriceQuote(
                provider = providerTitle(quote.provider),
                amountCNY = quote.amountCNY.takeIf { it > 0 },
                unit = if (quote.unit == "total") QuoteUnit.TOTAL else QuoteUnit.PER_NIGHT,
                kind = if (quote.kind == "indicative") QuoteKind.INDICATIVE else QuoteKind.LIVE,
                capturedAt = quote.capturedAt,
                bookingURL = quote.bookingURL,
                note = quote.note.orEmpty().ifBlank { "最终房型、税费与退改以结算页为准" }
            )
        }.groupBy({ it.first }, { it.second })
    }

    private suspend fun fetchTransportOptions(
        baseURL: URL,
        draft: TripDraft,
        accessPoints: List<AccessPoint>,
        accommodation: AccommodationOption?
    ): List<TransportOption> {
        val payload = TransportRequest(
            origin = draft.origin,
            destination = draft.destination,
            departureDate = draft.startDate,
            returnDate = LocalDate.parse(draft.startDate)
                .plusDays((draft.dayCount - 1).coerceAtLeast(0).toLong()).toString(),
            adults = draft.travelers,
            modes = listOf("train", "flight")
        )
        val response = json.decodeFromString<TransportResponse>(
            request(URL(baseURL, "v1/quotes/transport"), "POST", json.encodeToString(payload))
        )
        return response.options.mapNotNull { item ->
            val mode = when (item.mode) {
                "train" -> LongDistanceMode.TRAIN
                "flight" -> LongDistanceMode.FLIGHT
                else -> return@mapNotNull null
            }
            val hub = accessPoints.filter { it.kind == mode }.minByOrNull { nameDistance(it.name, item.destinationName) }
            val transfer = if (hub != null && accommodation != null) {
                hub.coordinate.distanceTo(accommodation.coordinate).roundToInt()
            } else null
            TransportOption(
                mode = mode,
                title = "${item.serviceNumber} · ${item.originName}→${item.destinationName}",
                originName = item.originName,
                destinationName = item.destinationName,
                departureTime = clockText(item.departureTime),
                arrivalTime = clockText(item.arrivalTime),
                durationMinutes = item.durationMinutes,
                arrivalAccessPoint = hub,
                hotelTransferMeters = transfer,
                quotes = listOf(
                    PriceQuote(
                        provider = providerTitle(item.provider),
                        amountCNY = item.amountCNY,
                        unit = QuoteUnit.PER_PERSON,
                        kind = if (item.amountCNY == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.LIVE,
                        capturedAt = item.capturedAt,
                        bookingURL = item.bookingURL,
                        note = "${item.fareName} · ${item.note}"
                    )
                ),
                recommendationReasons = buildList {
                    add("${clockText(item.departureTime)}–${clockText(item.arrivalTime)} · ${item.availability}")
                    if (hub != null && transfer != null) add("${hub.name}到住宿${transfer.distanceText()}")
                },
                isRecommended = false
            )
        }
    }

    private suspend fun request(url: URL, method: String, body: String?): String = withContext(Dispatchers.IO) {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 8_000
            readTimeout = 35_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "AnyTravel-Android/0.4 (+https://github.com/Rseam-07/AnyTravel)")
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
        }
        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) throw PricingException("节点返回 HTTP $status")
            text
        } finally {
            connection.disconnect()
        }
    }

    private fun normalizeBaseURL(value: String): URL {
        val trimmed = value.trim()
        if (trimmed.isBlank()) throw PricingException("请先在设置中填写报价节点地址")
        val uri = runCatching { URI(trimmed) }.getOrNull()
            ?: throw PricingException("报价节点地址格式不正确")
        if (uri.scheme !in setOf("http", "https") || uri.host.isNullOrBlank()) {
            throw PricingException("报价节点必须使用 http 或 https")
        }
        return URL(trimmed.trimEnd('/') + "/")
    }

    private fun normalizedName(value: String) = value.lowercase()
        .replace("酒店", "")
        .replace("宾馆", "")
        .replace(" ", "")

    private fun providerTitle(value: String) = when (value.lowercase()) {
        "rollinggo" -> "RollingGo"
        "ctrip" -> "携程"
        "12306" -> "铁路12306"
        else -> value
    }

    private fun nameDistance(lhs: String, rhs: String): Int {
        val left = lhs.replace("站", "").replace(" ", "")
        val right = rhs.replace("站", "").replace(" ", "")
        return when {
            left == right -> 0
            left.contains(right) || right.contains(left) -> 1
            else -> 10
        }
    }

    private fun clockText(value: String): String = runCatching {
        DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault()).format(Instant.parse(value))
    }.getOrDefault(value.takeLast(5))
}

data class PricingRefreshResult(
    val accommodationQuotes: Map<String, List<PriceQuote>>,
    val transports: List<TransportOption>,
    val message: String,
    val discoveredAccommodations: List<AccommodationOption> = emptyList()
)

class PricingException(message: String) : Exception(message)

@Serializable
private data class HotelRequest(val id: String, val name: String, val latitude: Double, val longitude: Double)

@Serializable
private data class AccommodationRequest(
    val destination: String,
    val checkIn: String,
    val checkOut: String,
    val adults: Int,
    val rooms: Int,
    val hotels: List<HotelRequest>
)

@Serializable
private data class AccommodationResponse(val quotes: List<BackendAccommodationQuote> = emptyList())

@Serializable
private data class BackendAccommodationQuote(
    val hotelID: String? = null,
    val hotelName: String,
    val provider: String,
    val amountCNY: Int,
    val unit: String = "per_night",
    val kind: String = "live",
    val capturedAt: String? = null,
    val bookingURL: String? = null,
    val note: String? = null
)

@Serializable
private data class TransportRequest(
    val origin: String,
    val destination: String,
    val departureDate: String,
    val returnDate: String?,
    val adults: Int,
    val modes: List<String>
)

@Serializable
private data class TransportResponse(val options: List<BackendTransportOption> = emptyList())

@Serializable
private data class BackendTransportOption(
    val provider: String,
    val mode: String,
    val serviceNumber: String,
    val originName: String,
    val destinationName: String,
    val departureTime: String,
    val arrivalTime: String,
    val durationMinutes: Int? = null,
    val amountCNY: Int? = null,
    val fareName: String = "票价待确认",
    val availability: String = "余票待确认",
    val bookingURL: String? = null,
    val capturedAt: String? = null,
    val note: String = "提交订单前请再次确认"
)
