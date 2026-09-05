package cn.anytravel.app.data

import android.annotation.SuppressLint
import cn.anytravel.app.BuildConfig
import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.TransportDirection
import cn.anytravel.app.model.TransportOption
import cn.anytravel.app.model.distanceText
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.add
import java.net.URI
import java.net.URLEncoder
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/** Public, account-free price sources embedded in the app. */
class DirectPricingClient {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val railwaySocketFactory: SSLSocketFactory? by lazy(::buildRailwaySocketFactory)

    suspend fun refresh(plan: CompletePlan, accessPoints: List<AccessPoint>): PricingRefreshResult = coroutineScope {
        val rollingGoHotels = async {
            if (plan.draft.skipAccommodation) DirectHotels() else searchRollingGo(plan, accessPoints)
        }
        val accorHotels = async {
            if (plan.draft.skipAccommodation) DirectHotels() else searchAccorOfficial(plan, accessPoints)
        }
        val officialHotels = async {
            if (plan.draft.skipAccommodation) DirectHotels() else searchHiltonOfficial(plan, accessPoints)
        }
        val railway = async { if (plan.draft.skipTransport) DirectTransport() else searchRailway(plan, accessPoints) }
        val flights = async { if (plan.draft.skipTransport) DirectTransport() else searchFlights(plan, accessPoints) }
        val rollingGoResult = rollingGoHotels.await()
        val accorResult = accorHotels.await()
        val officialResult = officialHotels.await()
        val hotelResult = DirectHotels(
            // RollingGo remains first so its live inventory wins the primary
            // card position; official sites add comparable quotes and fallback.
            options = AccommodationMerger.merge(rollingGoResult.options + accorResult.options + officialResult.options),
            issues = rollingGoResult.issues + accorResult.issues + officialResult.issues
        )
        val railResult = railway.await()
        val flightResult = flights.await()
        val transports = deduplicateTransports(railResult.options + flightResult.options)
        val issueText = (hotelResult.issues + railResult.issues + flightResult.issues).distinct().take(2)
        val pricedHotels = hotelResult.options.count { option -> option.quotes.any { it.amountCNY != null } }
        val pricedTrips = transports.count { option -> option.quotes.any { it.amountCNY != null } }
        PricingRefreshResult(
            accommodationQuotes = emptyMap(),
            transports = transports,
            discoveredAccommodations = hotelResult.options,
            message = buildString {
                append("已带回${pricedHotels}家住宿价格、${pricedTrips}个班次/航班报价")
                if (issueText.isNotEmpty()) append("；${issueText.joinToString("；")}")
            }
        )
    }

    /** Selected-date public rates from the current Accor web search and booking flow. */
    private suspend fun searchAccorOfficial(plan: CompletePlan, accessPoints: List<AccessPoint>): DirectHotels {
        val draft = plan.draft
        val checkIn = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
            ?: return DirectHotels(issues = listOf("雅高官网入住日期无法识别"))
        val nights = draft.nights.coerceAtLeast(1)
        val checkOut = checkIn.plusDays(nights.toLong())
        return runCatching {
            val index = if (draft.destination.any { it.code in 0x3400..0x9FFF }) "prod_hotels_zh" else "prod_hotels_en"
            val catalogBody = buildJsonObject {
                put("query", draft.destination.trim())
                put("hitsPerPage", 8)
                put("attributesToRetrieve", buildJsonArray {
                    listOf(
                        "objectID", "name", "brandLabel", "brand", "stars", "rating", "localization",
                        "freeAmenities", "paidAmenities", "mediaCatalog", "medias", "description",
                        "enhancedDescription", "labels", "thematics"
                    ).forEach { add(it) }
                })
                put("filters", "status:OPEN")
            }.toString()
            val catalog = request(
                URL("https://${ACCOR_ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/$index/query"),
                method = "POST",
                body = catalogBody,
                headers = mapOf(
                    "X-Algolia-Application-Id" to ACCOR_ALGOLIA_APP_ID,
                    "X-Algolia-API-Key" to ACCOR_ALGOLIA_SEARCH_KEY,
                    "Content-Type" to "application/json",
                    "Origin" to "https://all.accor.com",
                    "Referer" to "https://all.accor.com/"
                ),
                readTimeout = 15_000
            )
            val rows = json.parseToJsonElement(catalog.body).asObject()?.get("hits")?.asArray().orEmpty().take(8)
            val capturedAt = Instant.now().toString()
            val stopCoordinates = plan.days.flatMap { it.stops }.map { it.coordinate }
            val options = coroutineScope {
                rows.map { row ->
                    async {
                        val hotel = row.asObject() ?: return@async null
                        val code = hotel["objectID"]?.stringValue()?.trim().orEmpty()
                        val name = hotel["name"]?.stringValue()?.trim().orEmpty()
                        if (code.isBlank() || name.length < 2) return@async null
                        val rate = runCatching { accorRate(code, checkIn, checkOut, draft.travelers) }.getOrNull()
                        accorHotelOption(
                            hotel = hotel,
                            code = code,
                            name = name,
                            rate = rate,
                            nights = nights,
                            checkIn = checkIn,
                            checkOut = checkOut,
                            travelers = draft.travelers,
                            capturedAt = capturedAt,
                            stopCoordinates = stopCoordinates,
                            accessPoints = accessPoints
                        )
                    }
                }.awaitAll().filterNotNull()
            }
            val priced = options.count { option -> option.quotes.any { it.amountCNY != null } }
            DirectHotels(
                options = options,
                issues = when {
                    options.isEmpty() -> listOf("雅高官网暂未返回匹配酒店")
                    priced == 0 -> listOf("雅高官网已有酒店目录，所选日期暂未见公开房价")
                    else -> emptyList()
                }
            )
        }.getOrElse { DirectHotels(issues = listOf("雅高官网暂时没有回应：${shortError(it)}")) }
    }

    private suspend fun accorRate(code: String, checkIn: LocalDate, checkOut: LocalDate, travelers: Int): JsonObject? {
        val body = buildJsonObject {
            put("operationName", "HotelPageHot")
            put("query", ACCOR_HOTEL_OFFERS_QUERY)
            put("variables", buildJsonObject {
                put("hotelOffersHotelId", code)
                put("dateIn", checkIn.toString())
                put("dateOut", checkOut.toString())
                put("nbAdults", travelers.coerceIn(1, 8))
                put("childrenAges", buildJsonArray { })
                put("selectionStep", 0)
                put("countryMarket", "CN")
                put("currency", "CNY")
                put("offersSelectionFilters", buildJsonObject {
                    put("cancellationPolicies", JsonNull)
                    put("isAccessible", false)
                    put("mealPlans", JsonNull)
                })
                put("concession", JsonNull)
                put("use", "NIGHT")
                put("hideMemberRate", false)
                put("selection", buildJsonArray { })
            })
        }.toString()
        val response = request(
            URL(ACCOR_BFF_ENDPOINT),
            method = "POST",
            body = body,
            headers = mapOf(
                "apikey" to ACCOR_BFF_API_KEY,
                "app-id" to "all.accor",
                "app-version" to "1.39.1",
                "clientid" to "all.accor",
                "lang" to "zh",
                "Content-Type" to "application/json",
                "Origin" to "https://all.accor.com",
                "Referer" to "https://all.accor.com/"
            ),
            readTimeout = 15_000
        )
        val root = json.parseToJsonElement(response.body).asObject()
        val hotelOffers = root?.get("data")?.asObject()?.get("hotelOffers")?.asObject() ?: return null
        val status = hotelOffers["availability"]?.asObject()?.get("status")?.stringValue()
        if (status != "AVAILABLE") return null
        return hotelOffers["offersSelection"]?.asObject()?.get("offers")?.asArray().orEmpty()
            .mapNotNull(JsonElement::asObject)
            .filter { it["pricing"]?.asObject()?.get("main")?.asObject()?.get("amount")?.numberValue()?.let { amount -> amount > 0 } == true }
            .minByOrNull { it["pricing"]?.asObject()?.get("main")?.asObject()?.get("amount")?.numberValue() ?: Double.MAX_VALUE }
    }

    private fun accorHotelOption(
        hotel: JsonObject,
        code: String,
        name: String,
        rate: JsonObject?,
        nights: Int,
        checkIn: LocalDate,
        checkOut: LocalDate,
        travelers: Int,
        capturedAt: String,
        stopCoordinates: List<Coordinate>,
        accessPoints: List<AccessPoint>
    ): AccommodationOption? {
        val localization = hotel["localization"]?.asObject()
        val coordinateValue = localization?.get("gps")?.asObject()
        val latitude = coordinateValue?.get("lat")?.numberValue() ?: return null
        val longitude = coordinateValue["lng"]?.numberValue() ?: return null
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
        val coordinate = Coordinate(latitude, longitude)
        val averageDistance = stopCoordinates.ifEmpty { listOf(coordinate) }
            .map { it.distanceTo(coordinate) }.average().roundToInt()
        val hubDistance = accessPoints.minOfOrNull { it.coordinate.distanceTo(coordinate) }?.roundToInt() ?: 0
        val pricing = rate?.get("pricing")?.asObject()?.get("main")?.asObject()
        val totalAmount = pricing?.get("amount")?.numberValue()?.takeIf { it > 0 }?.roundToInt()
        val amount = totalAmount?.let { (it.toDouble() / nights).roundToInt().coerceAtLeast(1) }
        val mealPlan = rate?.get("mealPlan")?.asObject()?.get("label")?.stringValue()
        val cancellation = pricing?.get("simplifiedPolicies")?.asObject()
            ?.get("cancellation")?.asObject()?.get("label")?.stringValue()
        val address = localization["address"]?.asObject()
        val bookingURL = URI("https://all.accor.com/ssr/app/accor/rates").withQuery(
            mapOf(
                "hotelCode" to code,
                "checkIn" to checkIn.toString(),
                "checkOut" to checkOut.toString(),
                "numberOfRooms" to "1",
                "adults" to travelers.coerceIn(1, 8).toString()
            )
        ).toString()
        val brand = hotel.first("brandLabel", "brand")?.stringValue()
        return AccommodationOption(
            id = "accor-$code",
            name = name,
            address = listOfNotNull(
                address?.first("street", "line1")?.stringValue(),
                address?.get("city")?.stringValue()
            ).filter { it.isNotBlank() }.joinToString("，"),
            coordinate = coordinate,
            averageAttractionDistanceMeters = averageDistance,
            hubDistanceMeters = hubDistance,
            quotes = listOf(
                PriceQuote(
                    provider = "住宿官网",
                    amountCNY = amount,
                    unit = QuoteUnit.PER_NIGHT,
                    kind = if (amount == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.LIVE,
                    capturedAt = capturedAt,
                    bookingURL = bookingURL,
                    note = if (amount == null) "前往雅高集团官网查看所选日期房型"
                    else "雅高官网所选日期公开价${mealPlan?.let { " · $it" }.orEmpty()}；结算前请复核税费与库存",
                    displayPriceText = amount?.let { "¥${it}起" },
                    sourceLabel = "雅高集团官网",
                    totalAmountCNY = totalAmount,
                    roomName = rate?.get("accommodation")?.asObject()?.get("code")?.stringValue(),
                    mealPlan = mealPlan,
                    cancellationPolicy = cancellation,
                    availability = amount?.let { "所选日期有公开报价" }
                )
            ),
            recommendationReasons = buildList {
                add("到已选景点平均${averageDistance.distanceText()}")
                if (hubDistance > 0) add("距最近枢纽${hubDistance.distanceText()}")
            },
            isRecommended = false,
            brand = brand,
            starRating = hotel["stars"]?.numberValue(),
            guestRating = hotel["rating"]?.asObject()?.get("score")?.numberValue(),
            imageURL = hotel["mediaCatalog"]?.asObject()?.get("1024x768")?.stringValue()?.validURL()
                ?: hotel["medias"]?.asObject()?.get("dmUrlCrop3by2")?.stringValue()?.validURL(),
            officialWebsiteURL = bookingURL,
            amenities = (hotel["freeAmenities"].stringArray() + hotel["paidAmenities"].stringArray()).distinct().take(16),
            tags = (hotel["labels"].stringArray() + hotel["thematics"].stringArray()).distinct().take(16),
            sources = listOf("雅高集团官网")
        )
    }

    /** Public Hilton China catalog fallback; its visible minPrice is kept indicative. */
    private suspend fun searchHiltonOfficial(plan: CompletePlan, accessPoints: List<AccessPoint>): DirectHotels {
        val draft = plan.draft
        val checkIn = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
            ?: return DirectHotels(issues = listOf("希尔顿官网入住日期无法识别"))
        return runCatching {
            val url = URI("https://console-lls.hilton.com.cn/cgi/api/app/hotel/zh-CN/search")
                .withQuery(mapOf("keywords" to draft.destination))
                .toURL()
            val root = json.parseToJsonElement(
                request(url, headers = mapOf("Accept" to "application/json", "Accept-Language" to "zh-CN,zh;q=0.9")).body
            ).jsonObject
            val rows = root["data"]?.asObject()?.get("hotels")?.asArray().orEmpty()
            val capturedAt = Instant.now().toString()
            val stops = plan.days.flatMap { it.stops }.map { it.coordinate }
            val options = rows.mapNotNull { value ->
                val hotel = value.asObject() ?: return@mapNotNull null
                val name = hotel.first("hotelName", "name")?.stringValue()?.trim().orEmpty()
                val code = hotel.first("hotelCode", "id")?.stringValue()?.trim().orEmpty()
                val location = hotel["location"]?.asObject()
                val coordinateValue = location?.get("coordinate")?.asObject() ?: hotel["coordinate"]?.asObject()
                val latitude = coordinateValue?.first("latitude", "lat")?.numberValue()
                val longitude = coordinateValue?.first("longitude", "lng")?.numberValue()
                if (name.length < 2 || code.isBlank() || latitude == null || longitude == null || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
                    return@mapNotNull null
                }
                val coordinate = Coordinate(latitude, longitude)
                val averageDistance = stops.ifEmpty { listOf(coordinate) }.map { it.distanceTo(coordinate) }.average().roundToInt()
                val hubDistance = accessPoints.minOfOrNull { it.coordinate.distanceTo(coordinate) }?.roundToInt() ?: 0
                val amount = hotel["minPrice"]?.numberValue()?.takeIf { it > 0 }?.roundToInt()
                val bookingURL = URI("https://www.hilton.com/zh-hans/book/reservation/deeplink/").withQuery(
                    mapOf(
                        "ctyhocn" to code,
                        "arrivalDate" to checkIn.toString(),
                        "departureDate" to checkIn.plusDays(draft.nights.coerceAtLeast(1).toLong()).toString(),
                        "room1NumAdults" to draft.travelers.coerceIn(1, 8).toString()
                    )
                ).toString()
                val brand = hiltonBrandName(hotel["brandCode"]?.stringValue())
                val sellingPoints = hotel["sellingPoints"].stringArray()
                val tags = hotel["tags"].stringArray()
                AccommodationOption(
                    id = "hilton-$code",
                    name = name,
                    address = location?.get("address")?.stringValue().orEmpty(),
                    coordinate = coordinate,
                    averageAttractionDistanceMeters = averageDistance,
                    hubDistanceMeters = hubDistance,
                    quotes = listOf(
                        PriceQuote(
                            provider = "希尔顿官网",
                            amountCNY = amount,
                            unit = QuoteUnit.PER_NIGHT,
                            kind = if (amount == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.INDICATIVE,
                            capturedAt = capturedAt,
                            bookingURL = bookingURL,
                            note = if (amount == null) "进入官网查看所选日期房型" else "官网公开参考起价；购买页已带入行程日期，请复核房型与库存",
                            displayPriceText = amount?.let { "¥${it}起" },
                            sourceLabel = "希尔顿官网",
                            availability = amount?.let { "官网公开起价" }
                        )
                    ),
                    recommendationReasons = buildList {
                        add("到已选景点平均${averageDistance.distanceText()}")
                        if (hubDistance > 0) add("距最近枢纽${hubDistance.distanceText()}")
                    },
                    isRecommended = false,
                    brand = brand,
                    imageURL = hotel["masterCover"]?.asObject()?.get("url")?.stringValue()?.validURL(),
                    officialWebsiteURL = bookingURL,
                    amenities = hotel["amenities"].stringArray().take(12),
                    tags = (sellingPoints + tags).distinct().take(12),
                    sources = listOf("希尔顿官网")
                )
            }.let(AccommodationMerger::merge).take(30)
            DirectHotels(options, if (options.isEmpty()) listOf("希尔顿官网暂未返回匹配酒店") else emptyList())
        }.getOrElse { DirectHotels(issues = listOf("希尔顿官网暂时没有回应：${shortError(it)}")) }
    }

    private suspend fun searchRollingGo(plan: CompletePlan, accessPoints: List<AccessPoint>): DirectHotels {
        val key = BuildConfig.ROLLINGGO_API_KEY.trim()
        if (key.isBlank()) return DirectHotels(issues = listOf("内置酒店价格源尚未配置"))
        val draft = plan.draft
        val checkIn = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
            ?: return DirectHotels(issues = listOf("入住日期无法识别"))
        val nights = draft.nights.coerceAtLeast(1)
        val body = buildJsonObject {
            put("jsonrpc", "2.0")
            put("method", "tools/call")
            put("params", buildJsonObject {
                put("name", "searchHotels")
                put("arguments", buildJsonObject {
                    put("originQuery", "查找${draft.destination}适合${draft.travelers}人入住的酒店、民宿和公寓，比较${nights}晚实时价格")
                    put("place", draft.destination)
                    put("placeType", "城市")
                    put("checkInParam", buildJsonObject {
                        put("adultCount", (draft.travelers / ((draft.travelers + 1) / 2).coerceAtLeast(1)).coerceIn(1, 8))
                        put("checkInDate", checkIn.toString())
                        put("stayNights", nights)
                    })
                    put("size", 20)
                })
            })
            put("id", Instant.now().epochSecond)
        }.toString()
        return runCatching {
            val response = request(
                URL("https://mcp.rollinggo.cn/mcp"),
                method = "POST",
                body = body,
                headers = mapOf(
                    "Accept" to "application/json, text/event-stream",
                    "Authorization" to "Bearer $key",
                    "Content-Type" to "application/json"
                ),
                readTimeout = 28_000
            )
            val root = json.parseToJsonElement(lastSsePayload(response.body))
            val textPayloads = root.jsonObject["result"]?.asObject()
                ?.get("content")?.asArray().orEmpty()
                .mapNotNull { it.asObject()?.get("text")?.stringValue() }
            val objects = buildList {
                textPayloads.forEach { payload ->
                    runCatching { json.parseToJsonElement(payload) }.getOrNull()?.let { collectHotelObjects(it, this) }
                }
            }
            val stops = plan.days.flatMap { it.stops }
            val capturedAt = Instant.now().toString()
            val options = objects.mapNotNull { hotel ->
                hotelOption(hotel, nights, capturedAt, stops.map { it.coordinate }, accessPoints)
            }.let(AccommodationMerger::merge)
                .sortedBy { it.quotes.mapNotNull(PriceQuote::amountCNY).minOrNull() ?: Int.MAX_VALUE }
                .take(40)
            DirectHotels(
                options = options,
                issues = if (options.isEmpty()) listOf("RollingGo 暂无匹配的带价住宿") else emptyList()
            )
        }.getOrElse { DirectHotels(issues = listOf("酒店价格暂时没有抵达：${shortError(it)}")) }
    }

    private fun collectHotelObjects(element: JsonElement, output: MutableList<JsonObject>) {
        when (element) {
            is JsonArray -> element.forEach { collectHotelObjects(it, output) }
            is JsonObject -> {
                val hasName = element.first("name", "hotelName", "nameCn", "hotel_name") != null
                val hasPrice = element.first("displayPrice", "minPrice", "price", "lowestPrice", "totalPrice") != null
                val hasLocation = element.first("latitude", "lat", "hotelLat", "hotelLatitude") != null &&
                    element.first("longitude", "lng", "lon", "hotelLng", "hotelLongitude") != null
                val hasMetadata = element.first("address", "hotelAddress", "brand", "starRating", "amenities", "hotelAmenities") != null
                if (hasName && (hasPrice || hasLocation || hasMetadata)) output += element
                element.values.forEach { collectHotelObjects(it, output) }
            }
            else -> Unit
        }
    }

    private fun hotelOption(
        hotel: JsonObject,
        nights: Int,
        capturedAt: String,
        stopCoordinates: List<Coordinate>,
        accessPoints: List<AccessPoint>
    ): AccommodationOption? {
        val name = hotel.first("name", "hotelName", "nameCn", "hotel_name")?.stringValue()?.trim().orEmpty()
        val latitude = hotel.first("latitude", "lat", "hotelLat", "hotelLatitude")?.numberValue() ?: return null
        val longitude = hotel.first("longitude", "lng", "lon", "hotelLng", "hotelLongitude")?.numberValue() ?: return null
        if (name.isBlank() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
        val coordinate = Coordinate(latitude, longitude)
        val priceObject = hotel["price"]?.asObject()
        val rawAmount = priceObject?.first("lowestPrice", "totalPrice", "displayPrice", "minPrice", "price", "message")?.numberValue()
            ?: hotel.first("displayPrice", "minPrice", "price", "lowestPrice", "totalPrice")?.numberValue()
        val isStayTotal = priceObject?.containsKey("totalPrice") == true ||
            priceObject?.get("message")?.stringValue()?.let { "总价" in it || "合计" in it } == true
        val amount = rawAmount?.takeIf { it > 0 }?.let {
            (if (isStayTotal) it / nights.coerceAtLeast(1) else it).roundToInt().coerceAtLeast(1)
        }
        val referenceCoordinates = stopCoordinates.ifEmpty { listOf(coordinate) }
        val averageDistance = referenceCoordinates.map { it.distanceTo(coordinate) }.average().roundToInt()
        val railDistance = accessPoints.filter { it.kind == LongDistanceMode.TRAIN }
            .minOfOrNull { it.coordinate.distanceTo(coordinate) }?.roundToInt() ?: 0
        val bookingURL = hotel.first("bookingUrl", "bookingURL", "url")?.stringValue()?.validURL()
        return AccommodationOption(
            id = hotel.first("hotelId", "hotelID", "id", "hotel_id")?.stringValue()?.takeIf { it.isNotBlank() }
                ?.let { "rollinggo-$it" } ?: "rollinggo-${AccommodationMerger.normalizedName(name)}",
            name = name,
            address = hotel.first("address", "hotelAddress", "addressCn")?.stringValue().orEmpty(),
            coordinate = coordinate,
            averageAttractionDistanceMeters = averageDistance,
            hubDistanceMeters = railDistance,
            quotes = listOf(
                PriceQuote(
                    provider = "RollingGo",
                    amountCNY = amount,
                    unit = QuoteUnit.PER_NIGHT,
                    kind = if (amount == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.LIVE,
                    capturedAt = capturedAt,
                    bookingURL = bookingURL,
                    note = if (amount == null) "已返回酒店资料，进入房型页查看当前价格" else "实时展示价；选定房型后仍需锁价确认",
                    displayPriceText = amount?.let { "¥${it}起" },
                    sourceLabel = "道旅 RollingGo",
                    totalAmountCNY = if (isStayTotal) rawAmount?.roundToInt() else null,
                    availability = if (amount == null) null else "当前搜索有报价"
                )
            ),
            recommendationReasons = buildList {
                add("到已选景点平均${averageDistance.distanceText()}")
                if (railDistance > 0) add("距高铁站${railDistance.distanceText()}")
            },
            isRecommended = false,
            brand = hotel.first("brand", "brandName", "hotelBrand")?.stringValue(),
            starRating = hotel.first("starRating", "star", "starLevel")?.numberValue(),
            guestRating = hotel.first("rating", "guestRating", "score", "reviewScore")?.numberValue(),
            imageURL = hotel.first("imageUrl", "imageURL", "coverImage", "cover")?.stringValue()?.validURL(),
            officialWebsiteURL = AccommodationMerger.officialWebsite(name, hotel.first("brand", "brandName", "hotelBrand")?.stringValue()),
            amenities = hotel.first("hotelAmenities", "amenities", "facilities", "facilityList", "services").stringArray().take(12),
            tags = hotel.first("tags", "labels", "themes").stringArray().take(10),
            sources = listOf("RollingGo")
        )
    }

    private suspend fun searchRailway(plan: CompletePlan, accessPoints: List<AccessPoint>): DirectTransport {
        val draft = plan.draft
        if (draft.origin.isBlank()) return DirectTransport(issues = listOf("补充出发地后才能读取火车班次"))
        val date = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
            ?: return DirectTransport(issues = listOf("出发日期无法识别"))
        return runCatching {
            val stationSource = request(
                URL("https://kyfw.12306.cn/otn/resources/js/framework/station_name.js"),
                headers = railwayHeaders()
            ).body
            val stations = parseStations(stationSource)
            val from = findStation(stations, draft.origin) ?: return@runCatching DirectTransport(issues = listOf("12306 未找到${draft.origin}车站"))
            val to = findStation(stations, draft.destination) ?: return@runCatching DirectTransport(issues = listOf("12306 未找到${draft.destination}车站"))
            val journeys = buildList {
                add(RailJourney(TransportDirection.OUTBOUND, date, from, to))
                if (draft.dayCount > 1) add(RailJourney(TransportDirection.RETURN, date.plusDays((draft.dayCount - 1).toLong()), to, from))
            }
            val results = coroutineScope { journeys.map { async { searchRailJourney(it, accessPoints, plan.selectedAccommodation) } }.awaitAll() }
            DirectTransport(options = results.flatten())
        }.getOrElse { DirectTransport(issues = listOf("12306 班次暂时没有抵达：${shortError(it)}")) }
    }

    private suspend fun searchRailJourney(
        journey: RailJourney,
        accessPoints: List<AccessPoint>,
        accommodation: AccommodationOption?
    ): List<TransportOption> {
        val initURL = URI("https://kyfw.12306.cn/otn/leftTicket/init").withQuery(
            mapOf(
                "linktypeid" to "dc",
                "fs" to "${journey.from.name},${journey.from.code}",
                "ts" to "${journey.to.name},${journey.to.code}",
                "date" to journey.date.toString(),
                "flag" to "N,N,Y"
            )
        ).toURL()
        val init = request(initURL, headers = railwayHeaders())
        val cookie = init.headers.entries.filter { it.key.equals("Set-Cookie", true) }
            .flatMap { it.value }.map { it.substringBefore(';') }.joinToString("; ")
        val headers = railwayHeaders() + if (cookie.isBlank()) emptyMap() else mapOf("Cookie" to cookie)
        val queryURL = URI("https://kyfw.12306.cn/otn/leftTicket/query").withQuery(
            mapOf(
                "leftTicketDTO.train_date" to journey.date.toString(),
                "leftTicketDTO.from_station" to journey.from.code,
                "leftTicketDTO.to_station" to journey.to.code,
                "purpose_codes" to "ADULT"
            )
        ).toURL()
        val root = json.parseToJsonElement(request(queryURL, headers = headers).body).jsonObject
        if (root["status"]?.jsonPrimitive?.booleanOrNull != true) return emptyList()
        val data = root["data"]?.asObject() ?: return emptyList()
        val stationMap = data["map"]?.asObject().orEmpty().mapValues { it.value.stringValue().orEmpty() }
        val trains = data["result"]?.asArray().orEmpty().mapNotNull { row ->
            parseTrain(row.stringValue().orEmpty(), stationMap)
        }.filter { it.canBuy }.sortedWith(
            compareBy<RailTrain> { if (it.serviceNumber.firstOrNull() in listOf('G', 'D', 'C')) 0 else 1 }
                .thenBy { if (it.departureTime in "06:00".."20:30") 0 else 1 }
                .thenBy { it.durationMinutes ?: 9_999 }
                .thenBy { it.departureTime }
        ).take(8)
        return coroutineScope {
            trains.map { train -> async { railOption(train, journey, headers, accessPoints, accommodation) } }.awaitAll()
        }
    }

    private suspend fun railOption(
        train: RailTrain,
        journey: RailJourney,
        headers: Map<String, String>,
        accessPoints: List<AccessPoint>,
        accommodation: AccommodationOption?
    ): TransportOption {
        val priceURL = URI("https://kyfw.12306.cn/otn/leftTicket/queryTicketPrice").withQuery(
            mapOf(
                "train_no" to train.trainNumber,
                "from_station_no" to train.fromStationNumber,
                "to_station_no" to train.toStationNumber,
                "seat_types" to train.seatTypes,
                "train_date" to journey.date.toString()
            )
        ).toURL()
        val fare = runCatching {
            val root = json.parseToJsonElement(request(priceURL, headers = headers).body).jsonObject
            parseFare(root["data"]?.asObject())
        }.getOrNull()
        val destinationHub = if (journey.direction == TransportDirection.OUTBOUND) {
            accessPoints.filter { it.kind == LongDistanceMode.TRAIN }.minByOrNull {
                nameDistance(it.name, train.destinationName)
            }
        } else null
        val transfer = if (destinationHub != null && accommodation != null) {
            destinationHub.coordinate.distanceTo(accommodation.coordinate).roundToInt()
        } else null
        val bookingURL = URI("https://kyfw.12306.cn/otn/leftTicket/init").withQuery(
            mapOf(
                "linktypeid" to "dc",
                "fs" to "${journey.from.name},${journey.from.code}",
                "ts" to "${journey.to.name},${journey.to.code}",
                "date" to journey.date.toString(),
                "flag" to "N,N,Y"
            )
        ).toString()
        return TransportOption(
            mode = LongDistanceMode.TRAIN,
            title = "${train.serviceNumber} · ${train.originName}→${train.destinationName}",
            originName = train.originName,
            destinationName = train.destinationName,
            departureTime = train.departureTime,
            arrivalTime = train.arrivalTime,
            durationMinutes = train.durationMinutes,
            arrivalAccessPoint = destinationHub,
            hotelTransferMeters = transfer,
            quotes = listOf(
                PriceQuote(
                    provider = "铁路12306",
                    amountCNY = fare?.amountCNY,
                    unit = QuoteUnit.PER_PERSON,
                    kind = if (fare == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.LIVE,
                    capturedAt = Instant.now().toString(),
                    bookingURL = bookingURL,
                    note = "${journey.direction.title}余票和票价来自铁路12306公开查询页，提交订单前请再次确认",
                    displayPriceText = fare?.let { "¥${it.amountCNY}" },
                    sourceLabel = "铁路12306",
                    availability = availability(train.availability)
                )
            ),
            recommendationReasons = buildList {
                add("${train.departureTime}–${train.arrivalTime} · ${availability(train.availability)}")
                if (destinationHub != null && transfer != null) add("${destinationHub.name}到住宿${transfer.distanceText()}")
            },
            isRecommended = false,
            direction = journey.direction
        )
    }

    private suspend fun searchFlights(plan: CompletePlan, accessPoints: List<AccessPoint>): DirectTransport {
        val draft = plan.draft
        if (draft.origin.isBlank()) return DirectTransport(issues = listOf("补充出发地后才能读取机票"))
        val start = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
            ?: return DirectTransport(issues = listOf("出发日期无法识别"))
        val originCode = airportCode(draft.origin) ?: return DirectTransport(issues = listOf("暂未识别${draft.origin}的民航代码"))
        val destinationCode = airportCode(draft.destination, accessPoints) ?: return DirectTransport(issues = listOf("暂未识别${draft.destination}的民航代码"))
        val journeys = buildList {
            add(FlightJourney(TransportDirection.OUTBOUND, start, draft.origin, draft.destination, originCode, destinationCode))
            if (draft.dayCount > 1) add(FlightJourney(TransportDirection.RETURN, start.plusDays((draft.dayCount - 1).toLong()), draft.destination, draft.origin, destinationCode, originCode))
        }
        val settled = coroutineScope {
            journeys.map { journey -> async { runCatching { searchFlightJourney(journey, accessPoints, plan.selectedAccommodation) } } }.awaitAll()
        }
        val options = settled.flatMap { it.getOrDefault(emptyList()) }
        val failures = settled.mapNotNull { it.exceptionOrNull()?.let(::shortError) }
        return DirectTransport(options, failures.map { "机票价格暂时没有抵达：$it" })
    }

    private suspend fun searchFlightJourney(
        journey: FlightJourney,
        accessPoints: List<AccessPoint>,
        accommodation: AccommodationOption?
    ): List<TransportOption> {
        val payload = buildJsonObject {
            // MTOP signs the exact JSON bytes; keep the same sorted-key order as iOS.
            put("arrCityCode", journey.arrivalCode)
            put("depCityCode", journey.departureCode)
            put("itineraryFilter", "0")
            put("leaveCabinClass", "0")
            put("leaveDate", journey.date.toString())
            put("searchType", 1)
            put("useAcrossAgent", 1)
        }.toString()
        val cookies = linkedMapOf<String, String>()
        var lastMessage = "没有返回可用航班"
        repeat(3) { attempt ->
            val token = cookies["_m_h5_tk"]?.substringBefore('_').orEmpty()
            val timestamp = System.currentTimeMillis().toString()
            val signature = md5("$token&$timestamp&12574478&$payload")
            val url = URI("https://h5api.m.taobao.com/h5/mtop.trip.flight.flightSearch/1.0/").withQuery(
                linkedMapOf(
                    "jsv" to "2.7.0",
                    "appKey" to "12574478",
                    "t" to timestamp,
                    "sign" to signature,
                    "api" to "mtop.trip.flight.flightSearch",
                    "v" to "1.0",
                    "type" to "originaljson",
                    "dataType" to "json",
                    "data" to payload
                )
            ).toURL()
            val response = request(
                url,
                headers = mapOf(
                    "Accept" to "application/json,text/plain,*/*",
                    "Accept-Language" to "zh-CN,zh;q=0.9",
                    "Referer" to "https://h5.m.taobao.com/trip/flight/search/index.html",
                    "User-Agent" to NetworkClient.userAgent
                ) + if (cookies.isEmpty()) emptyMap() else mapOf("Cookie" to cookies.entries.joinToString("; ") { "${it.key}=${it.value}" })
            )
            response.headers.entries.filter { it.key.equals("Set-Cookie", true) }.flatMap { it.value }.forEach { raw ->
                val pair = raw.substringBefore(';').split('=', limit = 2)
                if (pair.size == 2) cookies[pair[0]] = pair[1]
            }
            val root = json.parseToJsonElement(response.body).jsonObject
            if (root["ret"]?.toString()?.contains("SUCCESS") == true && root["data"]?.asObject()?.get("success")?.jsonPrimitive?.booleanOrNull == true) {
                return flightOptions(root["data"]!!.jsonObject, journey, accessPoints, accommodation)
            }
            lastMessage = root["ret"]?.toString()?.take(160) ?: lastMessage
            if (attempt < 2) kotlinx.coroutines.delay(350)
        }
        throw PricingException(lastMessage)
    }

    private fun flightOptions(
        data: JsonObject,
        journey: FlightJourney,
        accessPoints: List<AccessPoint>,
        accommodation: AccommodationOption?
    ): List<TransportOption> {
        val allowed = setOf("DIRECT", "TRANSFER", "TRANSFER_RECOMMEND", "STOP")
        val rows = data["items"]?.asArray().orEmpty().flatMap { groupElement ->
            val group = groupElement.asObject() ?: return@flatMap emptyList()
            if (group["itemType"]?.stringValue() !in allowed) return@flatMap emptyList()
            group["itemDatas"]?.asArray().orEmpty().mapNotNull(JsonElement::asObject)
        }
        val capturedAt = Instant.now().toString()
        val options = rows.mapNotNull { row ->
            val price = row["bestPrice"]?.intValue()?.takeIf { it > 0 } ?: return@mapNotNull null
            val departure = clock(row.first("depTime", "depTimeShow")?.stringValue()) ?: return@mapNotNull null
            val arrival = clock(row.first("arrTime", "arrTimeShow")?.stringValue()) ?: return@mapNotNull null
            val arrivalAirport = airportName(row, "arr")
            val departureAirport = airportName(row, "dep")
            val hub = if (journey.direction == TransportDirection.OUTBOUND) {
                accessPoints.filter { it.kind == LongDistanceMode.FLIGHT }.minByOrNull { nameDistance(it.name, arrivalAirport) }
            } else null
            val transfer = if (hub != null && accommodation != null) hub.coordinate.distanceTo(accommodation.coordinate).roundToInt() else null
            val airline = row.first("airlineChineseName", "airlineChineseShortName")?.stringValue().orEmpty()
            val flightNumber = row["flightName"]?.stringValue().orEmpty()
            val bookingURL = URI("https://h5.m.taobao.com/trip/flight/search/index.html").withQuery(
                mapOf("depCityCode" to journey.departureCode, "arrCityCode" to journey.arrivalCode, "depDate" to journey.date.toString())
            ).toString()
            TransportOption(
                mode = LongDistanceMode.FLIGHT,
                title = listOf(airline, flightNumber).filter(String::isNotBlank).joinToString(" ").ifBlank { "${journey.departureCity}→${journey.arrivalCity}" },
                originName = departureAirport.ifBlank { journey.departureCity },
                destinationName = arrivalAirport.ifBlank { journey.arrivalCity },
                departureTime = departure,
                arrivalTime = arrival,
                durationMinutes = row.first("duration", "flyTime", "durationMinutes")?.intValue(),
                arrivalAccessPoint = hub,
                hotelTransferMeters = transfer,
                quotes = listOf(
                    PriceQuote(
                        provider = "飞猪旅行",
                        amountCNY = price,
                        unit = QuoteUnit.PER_PERSON,
                        kind = QuoteKind.LIVE,
                        capturedAt = capturedAt,
                        bookingURL = bookingURL,
                        note = "公开航班页当前单程起价；税费、舱位和退改条件以提交订单前为准",
                        displayPriceText = "¥${price}起",
                        sourceLabel = "飞猪公开航班页",
                        availability = "舱位以结算页为准"
                    )
                ),
                recommendationReasons = buildList {
                    add("$departure–$arrival · 飞猪当前报价")
                    if (hub != null && transfer != null) add("${hub.name}到住宿${transfer.distanceText()}")
                },
                isRecommended = false,
                direction = journey.direction
            )
        }
        return options.distinctBy { "${it.direction}|${serviceNumber(it.title)}|${it.departureTime}|${it.quotes.firstOrNull()?.amountCNY}" }
            .sortedWith(compareBy<TransportOption> { it.quotes.firstOrNull()?.amountCNY ?: Int.MAX_VALUE }.thenBy { it.departureTime })
            .take(12)
    }

    private suspend fun request(
        url: URL,
        method: String = "GET",
        body: String? = null,
        headers: Map<String, String> = emptyMap(),
        readTimeout: Int = 18_000
    ): NetworkResponse {
        val response = NetworkClient.request(
            url = url,
            method = method,
            body = body?.toByteArray(StandardCharsets.UTF_8),
            headers = headers,
            readTimeoutMillis = readTimeout,
            configure = { connection ->
                if (connection is HttpsURLConnection && url.host.endsWith("12306.cn")) {
                    railwaySocketFactory?.let { connection.sslSocketFactory = it }
                }
            }
        )
        if (response.status !in 200..299) throw PricingException("HTTP ${response.status}")
        return response
    }

    private fun parseStations(source: String): List<Station> = source.split('@').mapNotNull { raw ->
        val fields = raw.replace(Regex("^var station_names\\s*=\\s*['\"]?"), "").split('|')
        if (fields.size < 8 || fields[1].isBlank() || fields[2].isBlank()) null
        else Station(fields[1], fields[2], fields[7].ifBlank { fields[1] })
    }.distinctBy { it.code }

    @SuppressLint("CustomX509TrustManager")
    private fun buildRailwaySocketFactory(): SSLSocketFactory? = runCatching {
        val systemFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply {
            init(null as KeyStore?)
        }
        val systemTrust = systemFactory.trustManagers.filterIsInstance<X509TrustManager>().first()
        val certificate = javaClass.getResourceAsStream("/cfca_ev_root.pem")?.use { stream ->
            CertificateFactory.getInstance("X.509").generateCertificate(stream)
        } ?: return null
        val customStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
            setCertificateEntry("cfca-ev-root", certificate)
        }
        val customFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply {
            init(customStore)
        }
        val customTrust = customFactory.trustManagers.filterIsInstance<X509TrustManager>().first()
        val combined = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                systemTrust.checkClientTrusted(chain, authType)
            }

            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                try {
                    systemTrust.checkServerTrusted(chain, authType)
                } catch (_: CertificateException) {
                    customTrust.checkServerTrusted(chain, authType)
                }
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> =
                systemTrust.acceptedIssuers + customTrust.acceptedIssuers
        }
        SSLContext.getInstance("TLS").apply { init(null, arrayOf(combined), null) }.socketFactory
    }.getOrNull()

    private fun findStation(stations: List<Station>, query: String): Station? {
        val target = normalizedStation(query)
        return stations.firstOrNull { normalizedStation(it.name) == target || normalizedStation(it.city) == target }
            ?: stations.firstOrNull { normalizedStation(it.name).contains(target) || target.contains(normalizedStation(it.name)) }
    }

    private fun parseTrain(row: String, stationMap: Map<String, String>): RailTrain? {
        val fields = row.split('|')
        if (fields.size < 36 || fields[2].isBlank() || fields[3].isBlank()) return null
        return RailTrain(
            trainNumber = fields[2], serviceNumber = fields[3],
            originName = stationMap[fields[6]] ?: fields[6], destinationName = stationMap[fields[7]] ?: fields[7],
            departureTime = fields[8], arrivalTime = fields[9], durationMinutes = duration(fields[10]),
            canBuy = fields[11] == "Y", fromStationNumber = fields[16], toStationNumber = fields[17], seatTypes = fields[35],
            availability = mapOf("商务座" to fields[32], "一等座" to fields[31], "二等座" to fields[30], "软卧" to fields[23], "硬卧" to fields[28], "硬座" to fields[29], "无座" to fields[26])
        )
    }

    private fun parseFare(data: JsonObject?): Fare? {
        if (data == null) return null
        val priority = listOf("O" to "二等座", "M" to "一等座", "A3" to "硬座", "A4" to "软座", "A1" to "硬卧", "A2" to "软卧", "9" to "商务座")
        for ((key, name) in priority) parseYuan(data[key]?.stringValue())?.let { return Fare(it, name) }
        data.forEach { (key, value) -> parseYuan(value.stringValue())?.let { return Fare(it, key) } }
        return null
    }

    private fun availability(values: Map<String, String>): String = values.entries.filter { (_, value) ->
        value == "有" || (value.toIntOrNull() ?: 0) > 0
    }.take(3).joinToString(" · ") { (label, value) -> "$label${if (value == "有") "有票" else value}" }
        .ifBlank { "余票以12306页面为准" }

    private fun airportCode(city: String, points: List<AccessPoint> = emptyList()): String? {
        val raw = city.trim().uppercase()
        if (raw.matches(Regex("^[A-Z]{3}$"))) return raw
        val candidates = listOf(city) + points.filter { it.kind == LongDistanceMode.FLIGHT }.map { it.name }
        return candidates.firstNotNullOfOrNull { candidate ->
            val normalized = normalizedCity(candidate).lowercase()
            airportCodes.entries.firstOrNull { normalized.contains(it.key) }?.value
        }
    }

    private fun airportName(row: JsonObject, prefix: String): String {
        val base = row.first("${prefix}AirportName", "${prefix}AirportShortName", "${prefix}AirportShow", "${prefix}AirportCode")?.stringValue().orEmpty()
        val terminal = row.first("${prefix}AirportTerm", "${prefix}Terminal")?.stringValue().orEmpty()
        return if (terminal.isBlank() || base.contains(terminal)) base else "$base $terminal"
    }

    private fun deduplicateTransports(options: List<TransportOption>): List<TransportOption> {
        val result = linkedMapOf<String, TransportOption>()
        options.forEach { option ->
            val key = "${option.mode}|${option.direction}|${serviceNumber(option.title)}|${option.departureTime}"
            val current = result[key]
            result[key] = if (current == null) option else current.copy(
                quotes = (current.quotes + option.quotes).distinctBy { "${it.provider}|${it.unit}" }
                    .sortedBy { it.amountCNY ?: Int.MAX_VALUE },
                recommendationReasons = (current.recommendationReasons + option.recommendationReasons).distinct()
            )
        }
        return result.values.sortedWith(
            compareBy<TransportOption> { if (it.direction == TransportDirection.OUTBOUND) 0 else 1 }
                .thenBy { it.quotes.mapNotNull(PriceQuote::amountCNY).minOrNull() ?: Int.MAX_VALUE }
                .thenBy { it.departureTime }
        )
    }

    private fun railwayHeaders() = mapOf(
        "Accept" to "application/json,text/plain,*/*",
        "Accept-Language" to "zh-CN,zh;q=0.9",
        "Referer" to "https://kyfw.12306.cn/otn/leftTicket/init",
        "X-Requested-With" to "XMLHttpRequest"
    )

    private fun lastSsePayload(value: String): String = value.lineSequence()
        .filter { it.startsWith("data:") }.lastOrNull()?.removePrefix("data:")?.trim() ?: value.trim()

    private fun hiltonBrandName(code: String?): String = when (code?.uppercase()) {
        "WA" -> "华尔道夫"
        "CH" -> "康莱德"
        "LX" -> "LXR"
        "HI" -> "希尔顿"
        "QQ" -> "嘉悦里"
        "DT" -> "希尔顿逸林"
        "UP" -> "格芮精选"
        "PY" -> "启缤精选"
        "ES" -> "希尔顿安泊"
        "HT", "RU" -> "希尔顿欢朋"
        "GI" -> "希尔顿花园"
        "HW" -> "欣庭"
        "UA" -> "希尔顿惠庭"
        else -> "希尔顿集团"
    }

    private fun normalizedStation(value: String) = value.trim().replace(Regex("(?:省|市|自治区|特别行政区|站)$"), "").replace(" ", "").lowercase()
    private fun normalizedCity(value: String) = value.trim().replace(Regex("特别行政区|壮族自治区|回族自治区|维吾尔自治区|自治区|省|市|国际机场|机场|航站楼|T\\d+|\\s"), "")
    private fun nameDistance(lhs: String, rhs: String): Int {
        val left = normalizedCity(lhs); val right = normalizedCity(rhs)
        return when { left == right -> 0; left.contains(right) || right.contains(left) -> 1; else -> 10 }
    }

    private fun serviceNumber(value: String) = Regex("(?i)\\b[A-Z0-9]{2}\\s?\\d{1,5}\\b").find(value)?.value?.replace(" ", "")?.uppercase() ?: value
    private fun duration(value: String): Int? = value.split(':').takeIf { it.size == 2 }?.let { (it[0].toIntOrNull() ?: return null) * 60 + (it[1].toIntOrNull() ?: return null) }
    private fun parseYuan(value: String?): Int? = value?.let { Regex("¥\\s*(\\d+(?:\\.\\d+)?)").find(it)?.groupValues?.get(1)?.toDoubleOrNull()?.roundToInt() }
    private fun clock(value: String?): String? = value?.let { Regex("(?:^|\\s)([0-2]?\\d:[0-5]\\d)(?:$|\\s)").findAll(it).lastOrNull()?.groupValues?.get(1) }?.let {
        val parts = it.split(':'); "%02d:%s".format(parts[0].toInt(), parts[1])
    }
    private fun md5(value: String) = MessageDigest.getInstance("MD5").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
    private fun shortError(error: Throwable) = (error.message ?: error::class.simpleName ?: "未知错误").take(180)

    private data class DirectHotels(val options: List<AccommodationOption> = emptyList(), val issues: List<String> = emptyList())
    private data class DirectTransport(val options: List<TransportOption> = emptyList(), val issues: List<String> = emptyList())
    private data class Station(val name: String, val code: String, val city: String)
    private data class RailJourney(val direction: TransportDirection, val date: LocalDate, val from: Station, val to: Station)
    private data class RailTrain(
        val trainNumber: String, val serviceNumber: String, val originName: String, val destinationName: String,
        val departureTime: String, val arrivalTime: String, val durationMinutes: Int?, val canBuy: Boolean,
        val fromStationNumber: String, val toStationNumber: String, val seatTypes: String, val availability: Map<String, String>
    )
    private data class Fare(val amountCNY: Int, val name: String)
    private data class FlightJourney(
        val direction: TransportDirection, val date: LocalDate, val departureCity: String, val arrivalCity: String,
        val departureCode: String, val arrivalCode: String
    )

    companion object {
        private const val ACCOR_ALGOLIA_APP_ID = "TEBW21BCFZ"
        private const val ACCOR_ALGOLIA_SEARCH_KEY = "1a6f0c3b77791a299d98f6b981f2715d"
        private const val ACCOR_BFF_API_KEY = "l7xx5b9f4a053aaf43d8bc05bcc266dd8532"
        private const val ACCOR_BFF_ENDPOINT = "https://api.accor.com/bff/v1/graphql"
        private const val ACCOR_HOTEL_OFFERS_QUERY = """
            query HotelPageHot(
              ${'$'}hotelOffersHotelId: String!, ${'$'}dateIn: Date!, ${'$'}dateOut: Date!,
              ${'$'}nbAdults: PositiveInt!, ${'$'}childrenAges: [NonNegativeInt!],
              ${'$'}countryMarket: String!, ${'$'}currency: String!,
              ${'$'}offersSelectionFilters: OffersSelectionFilters,
              ${'$'}use: BestOfferUse, ${'$'}selectionStep: Int,
              ${'$'}concession: BestOfferConcession, ${'$'}hideMemberRate: Boolean,
              ${'$'}selection: [OfferSelectionInput!]
            ) {
              hotelOffers(
                hotelId: ${'$'}hotelOffersHotelId, dateIn: ${'$'}dateIn, dateOut: ${'$'}dateOut,
                nbAdults: ${'$'}nbAdults, childrenAges: ${'$'}childrenAges,
                countryMarket: ${'$'}countryMarket, currency: ${'$'}currency,
                use: ${'$'}use, concession: ${'$'}concession, hideMemberRate: ${'$'}hideMemberRate
              ) {
                offersSelection(selectionStep: ${'$'}selectionStep, filters: ${'$'}offersSelectionFilters, selection: ${'$'}selection) {
                  offers {
                    accommodation { code }
                    pricing { main { amount simplifiedPolicies { cancellation { label } } } }
                    mealPlan { label }
                  }
                }
                availability { status }
              }
            }
        """
        private val airportCodes = linkedMapOf(
            "苏南硕放" to "WUX", "上海虹桥" to "SHA", "上海浦东" to "SHA", "北京大兴" to "BJS", "北京首都" to "BJS",
            "成都天府" to "CTU", "成都双流" to "CTU", "西双版纳" to "JHG", "香格里拉" to "DIG", "乌鲁木齐" to "URC",
            "苏州" to "WUX", "无锡" to "WUX", "宁波" to "NGB", "栎社" to "NGB", "天津" to "TSN", "滨海" to "TSN",
            "上海" to "SHA", "北京" to "BJS", "广州" to "CAN", "深圳" to "SZX", "成都" to "CTU", "杭州" to "HGH",
            "南京" to "NKG", "武汉" to "WUH", "西安" to "SIA", "长沙" to "CSX", "厦门" to "XMN", "三亚" to "SYX",
            "海口" to "HAK", "昆明" to "KMG", "重庆" to "CKG", "青岛" to "TAO", "郑州" to "CGO", "济南" to "TNA",
            "沈阳" to "SHE", "大连" to "DLC", "长春" to "CGQ", "太原" to "TYN", "南昌" to "KHN", "合肥" to "HFE",
            "贵阳" to "KWE", "南宁" to "NNG", "兰州" to "LHW", "拉萨" to "LXA", "珠海" to "ZUH", "福州" to "FOC",
            "泉州" to "JJN", "温州" to "WNZ", "烟台" to "YNT", "徐州" to "XUZ", "南通" to "NTG", "扬州" to "YTY",
            "惠州" to "HUZ", "揭阳" to "SWA", "佛山" to "FUO", "桂林" to "KWL", "丽江" to "LJG", "大理" to "DLU",
            "腾冲" to "TCZ", "银川" to "INC", "西宁" to "XNN", "喀什" to "KHG", "香港" to "HKG", "澳门" to "MFM", "台北" to "TPE"
        )
    }
}

private fun URI.withQuery(values: Map<String, String>): URI {
    val query = values.entries.joinToString("&") { (key, value) ->
        "${URLEncoder.encode(key, StandardCharsets.UTF_8.name())}=${URLEncoder.encode(value, StandardCharsets.UTF_8.name())}"
    }
    // The multi-argument URI constructor escapes an already percent-encoded query a
    // second time ("%7B" becomes "%257B"), which invalidates MTOP signatures and
    // 12306 parameters. Build the final raw URI only after every value is encoded.
    val base = URI(scheme, authority, path, null, null).toASCIIString()
    return URI.create("$base?$query${fragment?.let { "#$it" }.orEmpty()}")
}

private fun JsonElement?.asObject(): JsonObject? = this as? JsonObject
private fun JsonElement?.asArray(): JsonArray? = this as? JsonArray
private fun JsonElement?.stringValue(): String? = (this as? JsonPrimitive)?.contentOrNull
private fun JsonElement?.numberValue(): Double? = (this as? JsonPrimitive)?.doubleOrNull
    ?: stringValue()?.let { Regex("\\d+(?:\\.\\d+)?").find(it)?.value?.toDoubleOrNull() }
private fun JsonElement?.intValue(): Int? = (this as? JsonPrimitive)?.intOrNull ?: numberValue()?.roundToInt()
private fun JsonObject.first(vararg keys: String): JsonElement? = keys.firstNotNullOfOrNull { this[it]?.takeUnless { value -> value is JsonNull } }
private fun JsonElement?.stringArray(): List<String> = asArray().orEmpty().mapNotNull { item ->
    item.stringValue()?.trim()?.takeIf(String::isNotEmpty)
        ?: item.asObject()?.first("name", "title", "label")?.stringValue()?.trim()?.takeIf(String::isNotEmpty)
}
private fun String.validURL(): String? = runCatching { URL(this).takeIf { it.protocol in setOf("http", "https") }?.toString() }.getOrNull()
