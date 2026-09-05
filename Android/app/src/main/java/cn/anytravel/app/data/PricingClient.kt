package cn.anytravel.app.data

import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.TransportOption
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.distanceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
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
        plan: CompletePlan,
        accessPoints: List<AccessPoint>
    ): PricingRefreshResult = coroutineScope {
        val normalized = normalizeBaseURL(baseURL)
        val draft = plan.draft
        val accommodations = plan.accommodations
        val catalogRequest = async {
            if (draft.skipAccommodation) emptyList() else fetchAccommodationCatalog(normalized, plan, accessPoints)
        }
        val hotelRequest = async {
            if (accommodations.isEmpty()) emptyMap() else fetchAccommodationQuotes(normalized, draft, accommodations)
        }
        val transportRequest = async {
            if (draft.skipTransport) emptyList() else fetchTransportOptions(normalized, draft, accessPoints, accommodations.firstOrNull())
        }
        val catalogResult = try {
            Result.success(catalogRequest.await())
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            Result.failure(error)
        }
        val hotelResult = try {
            Result.success(hotelRequest.await())
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            Result.failure(error)
        }
        val transportResult = try {
            Result.success(transportRequest.await())
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            Result.failure(error)
        }
        val failures = listOfNotNull(
            catalogResult.exceptionOrNull()?.message?.let { "酒店目录：$it" },
            hotelResult.exceptionOrNull()?.message?.let { "住宿：$it" },
            transportResult.exceptionOrNull()?.message?.let { "交通：$it" }
        )
        val discovered = catalogResult.getOrDefault(emptyList())
        val pricedDiscovered = discovered.count { option -> option.quotes.any { it.amountCNY != null } }
        PricingRefreshResult(
            accommodationQuotes = hotelResult.getOrDefault(emptyMap()),
            transports = transportResult.getOrDefault(emptyList()),
            discoveredAccommodations = discovered,
            message = when {
                failures.size == 3 -> throw PricingException(failures.joinToString("；"))
                failures.isNotEmpty() -> "已带回${discovered.size}家住宿（${pricedDiscovered}家有价格）；部分渠道没有返回：${failures.joinToString("；")}"
                else -> "已带回${discovered.size}家住宿（${pricedDiscovered}家有价格），价格与班次已按当前日期刷新"
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
            hotels = accommodations.map {
                HotelRequest(it.id, it.name, it.coordinate.latitude, it.coordinate.longitude, it.officialWebsiteURL)
            }
        )
        val response = json.decodeFromString<AccommodationResponse>(
            request(URL(baseURL, "v1/quotes/accommodations"), "POST", json.encodeToString(payload))
        )
        return response.quotes.mapNotNull { quote ->
            val option = accommodations.firstOrNull { it.id == quote.hotelID }
                ?: accommodations.firstOrNull {
                    AccommodationMerger.normalizedName(it.name) == AccommodationMerger.normalizedName(quote.hotelName)
                }
                ?: return@mapNotNull null
            option.id to PriceQuote(
                provider = providerTitle(quote.provider),
                amountCNY = quote.amountCNY.takeIf { it > 0 },
                unit = if (quote.unit == "total") QuoteUnit.TOTAL else QuoteUnit.PER_NIGHT,
                kind = if (quote.kind == "indicative") QuoteKind.INDICATIVE else QuoteKind.LIVE,
                capturedAt = quote.capturedAt,
                bookingURL = quote.bookingURL,
                note = quote.note.orEmpty().ifBlank { "最终房型、税费与退改以结算页为准" },
                totalAmountCNY = quote.totalAmountCNY,
                roomName = quote.roomName,
                bedType = quote.bedType,
                mealPlan = quote.mealPlan,
                cancellationPolicy = quote.cancellationPolicy,
                taxesIncluded = quote.taxesIncluded,
                availability = quote.availability
            )
        }.groupBy({ it.first }, { it.second })
    }

    private suspend fun fetchAccommodationCatalog(
        baseURL: URL,
        plan: CompletePlan,
        accessPoints: List<AccessPoint>
    ): List<AccommodationOption> {
        val draft = plan.draft
        val start = LocalDate.parse(draft.startDate)
        val payload = AccommodationCatalogRequest(
            destination = draft.destination,
            checkIn = start.toString(),
            checkOut = start.plusDays(draft.nights.toLong().coerceAtLeast(1)).toString(),
            adults = draft.travelers,
            rooms = ((draft.travelers + 1) / 2).coerceAtLeast(1),
            size = 20,
            anchors = plan.days.flatMap { it.stops }
                .sortedBy { it.popularityRank }
                .map { it.name }
                .distinct()
                .take(3)
        )
        val response = json.decodeFromString<AccommodationCatalogResponse>(
            request(URL(baseURL, "v1/accommodations/search"), "POST", json.encodeToString(payload))
        )
        val stopCoordinates = plan.days.flatMap { day -> day.stops.map { it.coordinate } }
            .ifEmpty { listOf(plan.destinationCenter) }
        return response.hotels.mapNotNull { hotel ->
            val latitude = hotel.latitude ?: return@mapNotNull null
            val longitude = hotel.longitude ?: return@mapNotNull null
            if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return@mapNotNull null
            val coordinate = Coordinate(latitude, longitude)
            val offers = hotel.offers.orEmpty().map { offer ->
                offer.toPriceQuote(response.capturedAt)
            }.ifEmpty {
                listOf(
                    BackendAccommodationOffer(
                        provider = hotel.provider ?: "unknown",
                        source = hotel.source,
                        amountCNY = hotel.amountCNY,
                        unit = hotel.unit,
                        kind = hotel.kind,
                        capturedAt = hotel.capturedAt,
                        bookingURL = hotel.bookingURL,
                        note = hotel.note ?: "到渠道查看当前房型和价格"
                    ).toPriceQuote(response.capturedAt)
                )
            }
            val attractionDistance = stopCoordinates.map { it.distanceTo(coordinate) }.average().roundToInt()
            val hubDistance = accessPoints.minOfOrNull { it.coordinate.distanceTo(coordinate) }
                ?.roundToInt() ?: 0
            val sources = (hotel.sources.orEmpty() + listOfNotNull(hotel.source))
                .filter(String::isNotBlank)
                .distinct()
            val officialURL = offers.firstOrNull { quote ->
                quote.sourceLabel == "希尔顿官网" || quote.provider == "住宿官网"
            }?.bookingURL
            AccommodationOption(
                id = "catalog-${hotel.providerHotelID}",
                name = hotel.name,
                address = hotel.address,
                coordinate = coordinate,
                averageAttractionDistanceMeters = attractionDistance,
                hubDistanceMeters = hubDistance,
                quotes = offers,
                recommendationReasons = buildList {
                    add("到已选景点平均${attractionDistance.distanceText()}")
                    if (hubDistance > 0) add("距抵达枢纽约${hubDistance.distanceText().removePrefix("约")}")
                    hotel.guestRating?.let { add("住客评分${"%.1f".format(it)}") }
                    if (sources.size > 1) add("${sources.size}个渠道同卡比价")
                },
                isRecommended = false,
                brand = hotel.brand,
                starRating = hotel.starRating,
                guestRating = hotel.guestRating,
                imageURL = hotel.imageURL,
                officialWebsiteURL = officialURL,
                amenities = hotel.amenities.take(12),
                tags = hotel.tags.take(10),
                sources = sources.map(::sourceTitle)
            )
        }.let(AccommodationMerger::merge)
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

    private suspend fun request(url: URL, method: String, body: String?): String {
        val response = NetworkClient.request(
            url = url,
            method = method,
            body = body?.toByteArray(Charsets.UTF_8),
            headers = if (body == null) emptyMap() else mapOf("Content-Type" to "application/json; charset=utf-8"),
            connectTimeoutMillis = 8_000,
            readTimeoutMillis = 35_000
        )
        if (response.status !in 200..299) throw PricingException("节点返回 HTTP ${response.status}")
        return response.body
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

    private fun providerTitle(value: String) = when (value.lowercase()) {
        "rollinggo" -> "RollingGo"
        "ctrip" -> "携程"
        "12306" -> "铁路12306"
        "official", "propertyofficial", "hilton-official", "accor-official" -> "住宿官网"
        else -> value
    }

    private fun sourceTitle(value: String) = when (value.lowercase()) {
        "rollinggo" -> "RollingGo"
        "ctrip-session", "onebound-ctrip" -> "携程"
        "tongcheng-session" -> "同程"
        "elong-open-api" -> "艺龙开放平台"
        "accor-official" -> "雅高集团官网"
        "hilton-official" -> "希尔顿官网"
        else -> value
    }

    private fun BackendAccommodationOffer.toPriceQuote(fallbackCapturedAt: String): PriceQuote {
        val amount = amountCNY?.takeIf { it > 0 }
        return PriceQuote(
            provider = providerTitle(provider),
            amountCNY = amount,
            unit = when (unit?.lowercase()) {
                "total" -> QuoteUnit.TOTAL
                "perperson", "per_person" -> QuoteUnit.PER_PERSON
                else -> QuoteUnit.PER_NIGHT
            },
            kind = when (kind?.lowercase()) {
                "live" -> if (amount == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.LIVE
                "indicative" -> QuoteKind.INDICATIVE
                "budgetestimate" -> QuoteKind.BUDGET_ENVELOPE
                else -> QuoteKind.CHECK_ON_PROVIDER
            },
            capturedAt = capturedAt ?: fallbackCapturedAt,
            bookingURL = bookingURL,
            note = note,
            displayPriceText = amount?.let { "¥${it}起" },
            sourceLabel = source?.let(::sourceTitle),
            totalAmountCNY = totalAmountCNY,
            roomName = roomName,
            bedType = bedType,
            mealPlan = mealPlan,
            cancellationPolicy = cancellationPolicy,
            taxesIncluded = taxesIncluded,
            availability = availability
        )
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
private data class HotelRequest(
    val id: String,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val officialWebsiteURL: String? = null
)

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
private data class AccommodationCatalogRequest(
    val destination: String,
    val checkIn: String,
    val checkOut: String,
    val adults: Int,
    val rooms: Int,
    val size: Int,
    val anchors: List<String>
)

@Serializable
private data class AccommodationCatalogResponse(
    val hotels: List<BackendAccommodationCatalogHotel> = emptyList(),
    val capturedAt: String = Instant.now().toString()
)

@Serializable
private data class BackendAccommodationCatalogHotel(
    val providerHotelID: String,
    val provider: String? = null,
    val source: String? = null,
    val sources: List<String> = emptyList(),
    val name: String,
    val brand: String? = null,
    val address: String = "",
    val latitude: Double? = null,
    val longitude: Double? = null,
    val starRating: Double? = null,
    val guestRating: Double? = null,
    val imageURL: String? = null,
    val bookingURL: String? = null,
    val amenities: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val amountCNY: Int? = null,
    val unit: String? = null,
    val kind: String? = null,
    val capturedAt: String? = null,
    val note: String? = null,
    val offers: List<BackendAccommodationOffer>? = null
)

@Serializable
private data class BackendAccommodationOffer(
    val provider: String,
    val source: String? = null,
    val amountCNY: Int? = null,
    val totalAmountCNY: Int? = null,
    val unit: String? = null,
    val kind: String? = null,
    val capturedAt: String? = null,
    val bookingURL: String? = null,
    val note: String = "价格、库存与退改请在结算页复核",
    val roomName: String? = null,
    val bedType: String? = null,
    val mealPlan: String? = null,
    val cancellationPolicy: String? = null,
    val taxesIncluded: Boolean? = null,
    val availability: String? = null
)

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
    val note: String? = null,
    val totalAmountCNY: Int? = null,
    val roomName: String? = null,
    val bedType: String? = null,
    val mealPlan: String? = null,
    val cancellationPolicy: String? = null,
    val taxesIncluded: Boolean? = null,
    val availability: String? = null
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
