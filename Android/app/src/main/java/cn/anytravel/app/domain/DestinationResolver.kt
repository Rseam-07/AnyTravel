package cn.anytravel.app.domain

import android.location.Address
import android.location.Geocoder
import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationSeed
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripInterest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.Locale

class DestinationResolver(private val geocoder: Geocoder) {
    suspend fun resolve(draft: TripDraft): DestinationPack {
        DestinationCatalog.find(draft.destination)?.let { return it }
        return withContext(Dispatchers.IO) { resolveFromSystem(draft) }
    }

    @Suppress("DEPRECATION")
    private fun resolveFromSystem(draft: TripDraft): DestinationPack {
        val centerAddress = search(draft.destination, 1).firstOrNull()
            ?: throw DestinationResolutionException("没有找到“${draft.destination}”，请检查名称后再试")
        val center = centerAddress.coordinate()
        val places = draft.interests.flatMap { interest ->
            search("${draft.destination} ${interest.searchTerm}", 2).mapNotNull { address ->
                val name = address.featureName?.takeUnless { it.all(Char::isDigit) }
                    ?: address.locality
                    ?: return@mapNotNull null
                TravelPlace(
                    name = name,
                    address = address.getAddressLine(0).orEmpty(),
                    coordinate = address.coordinate(),
                    interest = interest,
                    introduction = introductionFor(interest),
                    source = "Android 系统地理编码"
                )
            }
        }.distinctBy { "${it.name}-${"%.4f".format(it.coordinate.latitude)}-${"%.4f".format(it.coordinate.longitude)}" }
            .take((draft.dayCount * draft.pace.stopsPerDay).coerceAtLeast(4))
        if (places.size < 2) {
            throw DestinationResolutionException("已定位${draft.destination}，但暂时没有找到足够的真实地点，请稍后重试")
        }
        val hotels = search("${draft.destination} 酒店", 4).mapNotNull { address ->
            val name = address.featureName?.takeUnless { it.all(Char::isDigit) } ?: return@mapNotNull null
            AccommodationSeed(name, address.getAddressLine(0).orEmpty(), address.coordinate())
        }.distinctBy { it.name }.take(3)
        val fallbackHotels = if (hotels.isEmpty()) {
            listOf(AccommodationSeed("住宿位置待选择", "选择平台候选后地图会重新计算", center))
        } else hotels
        val rail = search("${draft.destination} 火车站", 2).firstOrNull()
        val airport = search("${draft.destination} 机场", 1).firstOrNull()
        val hubs = buildList {
            if (rail != null) add(AccessPoint(rail.featureName ?: "抵达车站", LongDistanceMode.TRAIN, rail.coordinate()))
            if (airport != null) add(AccessPoint(airport.featureName ?: "抵达机场", LongDistanceMode.FLIGHT, airport.coordinate()))
        }
        return DestinationPack(
            canonicalName = draft.destination,
            center = center,
            places = places,
            accommodations = fallbackHotels,
            accessPoints = hubs,
            sourceNote = "地点来自本机 Android 地理编码服务。路线为连线示意，名称、开放时间与实际道路请在出发前复核。"
        )
    }

    @Suppress("DEPRECATION")
    private fun search(query: String, limit: Int): List<Address> = try {
        geocoder.getFromLocationName(query, limit).orEmpty()
    } catch (error: IOException) {
        throw DestinationResolutionException("地点服务暂时没有回应，请检查网络后重试", error)
    } catch (error: IllegalArgumentException) {
        throw DestinationResolutionException("地点名称无法识别，请换一种写法", error)
    }

    private fun Address.coordinate() = Coordinate(latitude, longitude)

    private fun introductionFor(interest: TripInterest): String = when (interest) {
        TripInterest.GARDENS -> "把空间与建筑细节留给慢慢观看，出发前复核预约和开放时间。"
        TripInterest.CULTURE -> "适合把主要展陈与现场说明一起看，不必把每个展厅都赶完。"
        TripInterest.FOOD -> "在本地饮食与街巷之间留一段可随时停下来的时间。"
        TripInterest.NATURE -> "以舒适和少折返为先，天气变化时可以缩短停留。"
        TripInterest.FAMILY -> "安排更完整的休息间隔，并在出发前确认儿童设施。"
        TripInterest.NIGHT -> "作为晚间弹性安排，出发前确认亮灯和末班交通时间。"
    }
}

class DestinationResolutionException(message: String, cause: Throwable? = null) : Exception(message, cause)

fun createSystemGeocoder(context: android.content.Context): DestinationResolver =
    DestinationResolver(Geocoder(context, Locale.SIMPLIFIED_CHINESE))
