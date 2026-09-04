package cn.anytravel.app.model

import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

@Serializable
data class Coordinate(val latitude: Double, val longitude: Double) {
    fun distanceTo(other: Coordinate): Double {
        val earthRadius = 6_371_000.0
        val lat1 = Math.toRadians(latitude)
        val lat2 = Math.toRadians(other.latitude)
        val deltaLat = Math.toRadians(other.latitude - latitude)
        val deltaLon = Math.toRadians(other.longitude - longitude)
        val a = sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

@Serializable
enum class TripInterest(val title: String, val searchTerm: String) {
    GARDENS("园林建筑", "园林 景点"),
    CULTURE("人文博物馆", "博物馆 人文景点"),
    FOOD("本地美食", "老街 美食"),
    NATURE("自然慢逛", "公园 自然景点"),
    FAMILY("亲子体验", "亲子 景点"),
    NIGHT("夜间活动", "夜游 景点")
}

@Serializable
enum class TripPace(val title: String, val stopsPerDay: Int) {
    RELAXED("松弛", 2),
    BALANCED("适中", 3),
    FULL("充实", 4)
}

@Serializable
enum class LocalTravelMode(val title: String) {
    WALKING("步行优先"),
    TRANSIT("公交优先"),
    DRIVING("驾车")
}

@Serializable
enum class LongDistanceMode(val title: String) {
    TRAIN("高铁/火车"),
    FLIGHT("飞机"),
    DRIVING("自驾")
}

@Serializable
data class TripDraft(
    val origin: String = "上海",
    val destination: String = "苏州",
    val startDate: String = LocalDate.now().plusDays(14).toString(),
    val dayCount: Int = 3,
    val budgetPerPerson: Int = 3_000,
    val travelers: Int = 2,
    val interests: Set<TripInterest> = setOf(TripInterest.GARDENS, TripInterest.CULTURE, TripInterest.FOOD),
    val pace: TripPace = TripPace.RELAXED,
    val localTravelMode: LocalTravelMode = LocalTravelMode.WALKING,
    val preferredLongDistanceMode: LongDistanceMode? = null,
    val skipAccommodation: Boolean = false
) {
    val nights: Int get() = if (skipAccommodation) 0 else (dayCount - 1).coerceAtLeast(1)
}

@Serializable
data class TravelPlace(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val address: String,
    val coordinate: Coordinate,
    val interest: TripInterest,
    val introduction: String,
    val source: String,
    val popularityRank: Int = 999,
    val suggestedVisitMinutes: Int = 90,
    val openingHoursWeek: String? = null
)

@Serializable
data class ScheduleItem(
    val id: String,
    val timeText: String,
    val title: String,
    val detail: String,
    val placeId: String? = null
)

@Serializable
data class ItineraryDay(
    val index: Int,
    val stops: List<TravelPlace>,
    val schedule: List<ScheduleItem>
) {
    val title: String get() = "第 ${index + 1} 天"
}

@Serializable
enum class QuoteKind(val title: String) {
    LIVE("实时价"),
    INDICATIVE("参考价"),
    CHECK_ON_PROVIDER("到渠道查询"),
    BUDGET_ENVELOPE("预算预留")
}

@Serializable
enum class QuoteUnit(val title: String) {
    PER_NIGHT("每晚"),
    PER_PERSON("每人"),
    TOTAL("总价")
}

@Serializable
data class PriceQuote(
    val provider: String,
    val amountCNY: Int? = null,
    val unit: QuoteUnit,
    val kind: QuoteKind,
    val capturedAt: String? = null,
    val bookingURL: String? = null,
    val note: String,
    val displayPriceText: String? = null,
    val sourceLabel: String? = null,
    val totalAmountCNY: Int? = null,
    val availability: String? = null
)

@Serializable
data class AccommodationOption(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val address: String,
    val coordinate: Coordinate,
    val averageAttractionDistanceMeters: Int,
    val hubDistanceMeters: Int,
    val quotes: List<PriceQuote>,
    val recommendationReasons: List<String>,
    val isRecommended: Boolean,
    val brand: String? = null,
    val starRating: Double? = null,
    val guestRating: Double? = null,
    val imageURL: String? = null,
    val amenities: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val sources: List<String> = emptyList()
)

@Serializable
data class AccessPoint(
    val name: String,
    val kind: LongDistanceMode,
    val coordinate: Coordinate
)

@Serializable
enum class TransportDirection(val title: String) {
    OUTBOUND("去程"),
    RETURN("返程")
}

@Serializable
data class TransportOption(
    val id: String = UUID.randomUUID().toString(),
    val mode: LongDistanceMode,
    val title: String,
    val originName: String,
    val destinationName: String,
    val departureTime: String?,
    val arrivalTime: String?,
    val durationMinutes: Int?,
    val arrivalAccessPoint: AccessPoint?,
    val hotelTransferMeters: Int?,
    val quotes: List<PriceQuote>,
    val recommendationReasons: List<String>,
    val isRecommended: Boolean,
    val direction: TransportDirection = TransportDirection.OUTBOUND
)

@Serializable
enum class ExpenseSource(val title: String) {
    LIVE("实时价"),
    BUDGET("预算预留")
}

@Serializable
data class ExpenseLine(
    val id: String,
    val title: String,
    val detail: String,
    val amountCNY: Int,
    val source: ExpenseSource
)

@Serializable
data class DestinationPack(
    val canonicalName: String,
    val center: Coordinate,
    val places: List<TravelPlace>,
    val accommodations: List<AccommodationSeed>,
    val accessPoints: List<AccessPoint>,
    val sourceNote: String
)

@Serializable
data class AccommodationSeed(
    val name: String,
    val address: String,
    val coordinate: Coordinate
)

@Serializable
data class CompletePlan(
    val id: String = UUID.randomUUID().toString(),
    val createdAt: String = java.time.Instant.now().toString(),
    val draft: TripDraft,
    val destinationCenter: Coordinate,
    val days: List<ItineraryDay>,
    val accommodations: List<AccommodationOption>,
    val selectedAccommodationId: String?,
    val transports: List<TransportOption>,
    val selectedTransportId: String?,
    val expenses: List<ExpenseLine>,
    val sourceNote: String,
    val routeIsSchematic: Boolean = true,
    val selectedPlaceIDs: Set<String> = emptySet(),
    val planningNotes: List<String> = emptyList()
) {
    val selectedAccommodation: AccommodationOption?
        get() = accommodations.firstOrNull { it.id == selectedAccommodationId }
    val selectedTransport: TransportOption?
        get() = transports.firstOrNull { it.id == selectedTransportId }
    val totalExpense: Int get() = expenses.sumOf { it.amountCNY }
}

fun Int.distanceText(): String = when {
    this < 1_000 -> "约${this.coerceAtLeast(0)}米"
    else -> "约${"%.1f".format(this / 1_000.0)}公里"
}

fun Int.durationText(): String {
    val hours = this / 60
    val minutes = this % 60
    return when {
        hours == 0 -> "${minutes}分钟"
        minutes == 0 -> "${hours}小时"
        else -> "${hours}小时${minutes}分"
    }
}
