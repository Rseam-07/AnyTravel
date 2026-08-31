package cn.anytravel.app.domain

import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationSeed
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripInterest

object DestinationCatalog {
    private val suzhou = DestinationPack(
        canonicalName = "苏州",
        center = Coordinate(31.3050, 120.6200),
        places = listOf(
            place("拙政园", "姑苏区东北街178号", 31.3246, 120.6247, TripInterest.GARDENS, "从水院、长廊与漏窗之间慢慢读懂江南园林。"),
            place("苏州博物馆", "姑苏区东北街204号", 31.3247, 120.6224, TripInterest.CULTURE, "贝聿铭设计的新馆把粉墙黛瓦与现代几何安放在一起。"),
            place("平江路历史街区", "姑苏区平江路", 31.3118, 120.6307, TripInterest.FOOD, "沿河走一段旧城肌理，在桥、巷与小店之间留出闲坐时间。"),
            place("留园", "姑苏区留园路338号", 31.3155, 120.5848, TripInterest.GARDENS, "以精巧空间和太湖石闻名，适合避开匆忙的人流细看。"),
            place("虎丘山风景名胜区", "姑苏区虎丘山门内8号", 31.3382, 120.5765, TripInterest.NATURE, "山不高，却把古塔、剑池与吴地传说叠在一条缓坡上。"),
            place("山塘街", "姑苏区山塘街", 31.3182, 120.5981, TripInterest.NIGHT, "黄昏以后沿河灯火渐起，适合作为不赶时间的夜间散步。"),
            place("网师园", "姑苏区阔家头巷11号", 31.2980, 120.6298, TripInterest.CULTURE, "小园尺度亲近，宅与园的转折尤其适合慢慢体会。"),
            place("金鸡湖景区", "苏州工业园区星港街", 31.3173, 120.7045, TripInterest.FAMILY, "开阔湖岸适合亲子散步，也为密集的古城行程留一段呼吸。")
        ),
        accommodations = listOf(
            AccommodationSeed("苏州南园宾馆", "姑苏区带城桥路99号", Coordinate(31.2981, 120.6252)),
            AccommodationSeed("苏州平江华府精品酒店", "姑苏区临顿路菉葭巷88号", Coordinate(31.3164, 120.6240)),
            AccommodationSeed("苏州金普顿竹辉酒店", "姑苏区竹辉路168号", Coordinate(31.2927, 120.6260))
        ),
        accessPoints = listOf(
            AccessPoint("苏州站", LongDistanceMode.TRAIN, Coordinate(31.3291, 120.6060)),
            AccessPoint("苏州北站", LongDistanceMode.TRAIN, Coordinate(31.4220, 120.6440)),
            AccessPoint("苏南硕放国际机场", LongDistanceMode.FLIGHT, Coordinate(31.4944, 120.4294))
        ),
        sourceNote = "苏州地点采用仓库内人工核对的公开地理坐标；路线当前为地图连线示意，实际道路与开放时间请在出发前复核。"
    )

    private val aliases = mapOf(
        "苏州" to suzhou,
        "苏州市" to suzhou,
        "suzhou" to suzhou
    )

    fun find(destination: String): DestinationPack? = aliases[destination.trim().lowercase()]

    private fun place(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        interest: TripInterest,
        introduction: String
    ) = TravelPlace(
        name = name,
        address = address,
        coordinate = Coordinate(latitude, longitude),
        interest = interest,
        introduction = introduction,
        source = "人工核对的公开地理信息"
    )
}
