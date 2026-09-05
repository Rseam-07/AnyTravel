package cn.anytravel.app.data

import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.LocalTravelMode
import cn.anytravel.app.model.RouteSegment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.URI
import kotlin.math.roundToInt

/**
 * Adds road-level geometry without retaining a navigation engine or another
 * native map SDK in the process. Requests are deliberately limited to two at a
 * time so an older Android 12 device is not decoding every day simultaneously.
 */
class OpenRouteClient(
    private val endpoint: String = "https://valhalla1.openstreetmap.de/route"
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun routes(plan: CompletePlan): RouteRefreshResult = coroutineScope {
        val costing = when (plan.draft.localTravelMode) {
            LocalTravelMode.WALKING -> "pedestrian"
            LocalTravelMode.DRIVING -> "auto"
            // The public instance has no reliable China transit timetable. A
            // straight, clearly-labelled segment is safer than drawing a walk
            // route and calling it public transport.
            LocalTravelMode.TRANSIT -> null
        }
        val requests = plan.days.flatMap { day ->
            day.stops.zipWithNext().map { (from, to) ->
                RouteRequest(day.index, from.id, to.id, from.coordinate, to.coordinate)
            }
        }
        if (costing == null || requests.isEmpty()) {
            return@coroutineScope RouteRefreshResult(emptyList(), requests.size)
        }

        val gate = Semaphore(2)
        val outcomes = requests.map { request ->
            async {
                gate.withPermit {
                    try {
                        fetch(request, costing)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        null
                    }
                }
            }
        }.awaitAll()
        val segments = outcomes.filterNotNull()
        RouteRefreshResult(
            segments = segments,
            failedSegmentCount = (requests.size - segments.size).coerceAtLeast(0)
        )
    }

    private suspend fun fetch(request: RouteRequest, costing: String): RouteSegment {
        val body = buildJsonObject {
            put("locations", buildJsonArray {
                add(buildJsonObject {
                    put("lat", request.from.latitude)
                    put("lon", request.from.longitude)
                })
                add(buildJsonObject {
                    put("lat", request.to.latitude)
                    put("lon", request.to.longitude)
                })
            })
            put("costing", costing)
            put("units", "kilometers")
            put("language", "zh-CN")
        }.toString()
        val uri = URI(endpoint).let { base ->
            URI(base.scheme, base.authority, base.path, "json=$body", null)
        }
        val response = NetworkClient.request(
            url = uri.toURL(),
            headers = mapOf("Accept-Language" to "zh-CN,zh;q=0.9"),
            connectTimeoutMillis = 8_000,
            readTimeoutMillis = 18_000,
            maxResponseBytes = 2 * 1024 * 1024
        )
        if (response.status !in 200..299) throw PricingException("路线服务返回 HTTP ${response.status}")
        return withContext(Dispatchers.Default) { parse(response.body, request) }
    }

    private fun parse(payload: String, request: RouteRequest): RouteSegment {
        val root = json.parseToJsonElement(payload).jsonObject
        val trip = root["trip"]?.jsonObject ?: throw PricingException("路线服务没有返回旅程")
        val status = trip["status"]?.jsonPrimitive?.intOrNull ?: -1
        if (status != 0) throw PricingException(trip["status_message"]?.jsonPrimitive?.content ?: "路线服务没有找到道路")
        val leg = trip["legs"]?.jsonArray?.firstOrNull()?.jsonObject
            ?: throw PricingException("路线服务没有返回路段")
        val coordinates = decodePolyline6(leg["shape"]?.jsonPrimitive?.content.orEmpty())
        if (coordinates.size < 2) throw PricingException("路线几何为空")
        val summary: JsonObject = leg["summary"]?.jsonObject ?: JsonObject(emptyMap())
        val distanceMeters = ((summary["length"]?.jsonPrimitive?.doubleOrNull ?: 0.0) * 1_000)
            .roundToInt().coerceAtLeast(1)
        val durationMinutes = ((summary["time"]?.jsonPrimitive?.doubleOrNull ?: 0.0) / 60)
            .roundToInt().coerceAtLeast(1)
        return RouteSegment(
            id = "route-${request.dayIndex}-${request.fromPlaceID}-${request.toPlaceID}",
            dayIndex = request.dayIndex,
            fromPlaceID = request.fromPlaceID,
            toPlaceID = request.toPlaceID,
            coordinates = coordinates,
            distanceMeters = distanceMeters,
            durationMinutes = durationMinutes,
            source = "OpenStreetMap / Valhalla"
        )
    }
}

data class RouteRefreshResult(
    val segments: List<RouteSegment>,
    val failedSegmentCount: Int
)

private data class RouteRequest(
    val dayIndex: Int,
    val fromPlaceID: String,
    val toPlaceID: String,
    val from: Coordinate,
    val to: Coordinate
)

internal fun decodePolyline6(value: String): List<Coordinate> {
    if (value.isBlank()) return emptyList()
    var index = 0
    var latitude = 0L
    var longitude = 0L

    fun nextDelta(): Long? {
        var result = 0L
        var shift = 0
        while (index < value.length) {
            val byte = value[index++].code - 63
            if (byte < 0) return null
            result = result or ((byte and 0x1f).toLong() shl shift)
            if (byte < 0x20) return if ((result and 1L) != 0L) -(result shr 1) - 1 else result shr 1
            shift += 5
            if (shift > 60) return null
        }
        return null
    }

    val output = mutableListOf<Coordinate>()
    while (index < value.length) {
        val latitudeDelta = nextDelta() ?: return emptyList()
        val longitudeDelta = nextDelta() ?: return emptyList()
        latitude += latitudeDelta
        longitude += longitudeDelta
        output += Coordinate(latitude / 1_000_000.0, longitude / 1_000_000.0)
    }
    return output
}
