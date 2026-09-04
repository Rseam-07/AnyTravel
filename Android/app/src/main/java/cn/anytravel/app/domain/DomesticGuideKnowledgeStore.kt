package cn.anytravel.app.domain

import android.content.Context
import cn.anytravel.app.model.AccommodationSeed
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripInterest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The same generated destination snapshot used by iOS and Web. */
class DomesticGuideKnowledgeStore private constructor(
    private val cities: List<GuideCity>
) {
    fun destination(draft: TripDraft): DestinationPack? {
        val needle = normalizeCity(draft.destination)
        val city = cities.firstOrNull { normalizeCity(it.city) == needle } ?: return null
        val centre = city.coord?.toCoordinate() ?: return null
        val places = city.places.mapIndexedNotNull { index, place ->
            val coordinate = place.coord?.toCoordinate() ?: return@mapIndexedNotNull null
            val interest = interestFor(place.category)
            TravelPlace(
                name = place.name,
                address = "${city.city} · ${place.tags.take(2).joinToString(" · ")}",
                coordinate = coordinate,
                interest = interest,
                introduction = introductionFor(interest, place.tier),
                source = "AnyTravel 目的地资料（非实时）",
                popularityRank = index + 1,
                suggestedVisitMinutes = place.stayMinutes.coerceIn(45, 360),
                openingHoursWeek = place.openingHoursWeek
            )
        }
        if (places.size < 2) return null
        return DestinationPack(
            canonicalName = city.city,
            center = centre,
            places = places,
            accommodations = listOf(
                AccommodationSeed("住宿位置待选择", "实时酒店返回后会重新计算", centre)
            ),
            accessPoints = emptyList(),
            sourceNote = "景点来自内置的国内目的地资料，按公开热度和代表性排序；开放、预约与票价仍会在出发前核验。"
        )
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun fromAssets(context: Context): DomesticGuideKnowledgeStore {
            val text = context.assets.open("domestic_guide_knowledge.json")
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
            return fromJson(text)
        }

        internal fun fromJson(text: String): DomesticGuideKnowledgeStore =
            DomesticGuideKnowledgeStore(json.decodeFromString<GuideDocument>(text).cities)

        private fun normalizeCity(value: String): String = value
            .trim()
            .replace(Regex("\\s+"), "")
            .replace(Regex("(市|省|自治区|特别行政区)$"), "")

        private fun interestFor(category: String): TripInterest = when (category) {
            "博物馆", "美术馆", "科技馆", "剧院" -> TripInterest.CULTURE
            "自然", "山水", "海滨", "公园" -> TripInterest.NATURE
            "亲子", "乐园", "动物园" -> TripInterest.FAMILY
            "美食", "美食街" -> TripInterest.FOOD
            "夜游", "夜景" -> TripInterest.NIGHT
            else -> TripInterest.GARDENS
        }

        private fun introductionFor(interest: TripInterest, tier: String): String {
            val priority = if (tier == "必去") "代表性主游览点" else "可按距离和当天状态取舍"
            val rhythm = when (interest) {
                TripInterest.CULTURE -> "预留排队、安检和完整看展时间"
                TripInterest.NATURE -> "优先安排在白天，并随天气调整"
                TripInterest.FAMILY -> "保留餐食与休息间隔"
                TripInterest.FOOD -> "放在用餐时段，不再叠加一次正餐"
                TripInterest.NIGHT -> "作为晚间弹性段，先查末班交通"
                TripInterest.GARDENS -> "与附近街区同日编排，减少折返"
            }
            return "$priority；$rhythm。"
        }
    }
}

@Serializable
private data class GuideDocument(val cities: List<GuideCity> = emptyList())

@Serializable
private data class GuideCity(
    val city: String,
    val coord: GuideCoordinate? = null,
    val places: List<GuidePlace> = emptyList()
)

@Serializable
private data class GuidePlace(
    val name: String,
    val coord: GuideCoordinate? = null,
    val category: String = "古迹",
    val stayMinutes: Int = 90,
    val tier: String = "推荐",
    val tags: List<String> = emptyList(),
    val openingHoursWeek: String? = null
)

@Serializable
private data class GuideCoordinate(
    @SerialName("lat") val latitude: Double,
    @SerialName("lng") val longitude: Double
) {
    fun toCoordinate() = Coordinate(latitude, longitude)
}
