package cn.anytravel.app.domain

import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.ExpenseLine
import cn.anytravel.app.model.ExpenseSource
import cn.anytravel.app.model.ItineraryDay
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.ScheduleItem
import cn.anytravel.app.model.TransportOption
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripPace
import cn.anytravel.app.model.distanceText
import java.net.URLEncoder
import kotlin.math.roundToInt

class PlanBuilder {
    fun build(draft: TripDraft, pack: DestinationPack): CompletePlan {
        val orderedPlaces = orderPlaces(draft, pack)
        val days = buildDays(draft, orderedPlaces)
        val accommodations = buildAccommodations(draft, pack, days)
        val selectedAccommodation = accommodations.firstOrNull()
        val transports = buildTransports(draft, pack.accessPoints, selectedAccommodation)
        val selectedTransport = transports.firstOrNull()
        return CompletePlan(
            draft = draft,
            destinationCenter = pack.center,
            days = days,
            accommodations = accommodations,
            selectedAccommodationId = selectedAccommodation?.id,
            transports = transports,
            selectedTransportId = selectedTransport?.id,
            expenses = buildExpenses(draft, selectedAccommodation, selectedTransport),
            sourceNote = pack.sourceNote
        )
    }

    fun selectAccommodation(plan: CompletePlan, id: String): CompletePlan {
        val selected = plan.accommodations.firstOrNull { it.id == id } ?: return plan
        val accommodations = plan.accommodations.map { it.copy(isRecommended = it.id == id) }
        val transports = rerankTransports(plan.draft, plan.transports, selected)
        val selectedTransport = transports.firstOrNull()
        return plan.copy(
            accommodations = accommodations,
            selectedAccommodationId = id,
            transports = transports,
            selectedTransportId = selectedTransport?.id,
            expenses = buildExpenses(plan.draft, selected, selectedTransport)
        )
    }

    fun selectTransport(plan: CompletePlan, id: String): CompletePlan {
        val transport = plan.transports.firstOrNull { it.id == id } ?: return plan
        val transports = plan.transports.map { it.copy(isRecommended = it.id == id) }
        return plan.copy(
            transports = transports,
            selectedTransportId = id,
            expenses = buildExpenses(plan.draft, plan.selectedAccommodation, transport)
        )
    }

    fun mergeLiveData(
        plan: CompletePlan,
        accommodationQuotes: Map<String, List<PriceQuote>>,
        liveTransports: List<TransportOption>
    ): CompletePlan {
        val accommodations = plan.accommodations.map { option ->
            val live = accommodationQuotes[option.id].orEmpty()
            if (live.isEmpty()) option else option.copy(
                quotes = live + option.quotes.filter { fallback -> live.none { it.provider == fallback.provider } }
            )
        }.sortedBy { option ->
            option.quotes.filter { it.kind == QuoteKind.LIVE }.mapNotNull { it.amountCNY }.minOrNull()
                ?: Int.MAX_VALUE
        }
        val selectedAccommodationId = plan.selectedAccommodationId?.takeIf { id -> accommodations.any { it.id == id } }
            ?: accommodations.firstOrNull()?.id
        val selectedAccommodation = accommodations.firstOrNull { it.id == selectedAccommodationId }
        val transports = if (liveTransports.isEmpty()) {
            rerankTransports(plan.draft, plan.transports, selectedAccommodation)
        } else {
            val liveModes = liveTransports.map { it.mode }.toSet()
            rerankTransports(
                plan.draft,
                liveTransports + plan.transports.filterNot { it.mode in liveModes },
                selectedAccommodation
            )
        }
        val selectedTransport = transports.firstOrNull()
        return plan.copy(
            accommodations = accommodations.map { it.copy(isRecommended = it.id == selectedAccommodationId) },
            selectedAccommodationId = selectedAccommodationId,
            transports = transports,
            selectedTransportId = selectedTransport?.id,
            expenses = buildExpenses(plan.draft, selectedAccommodation, selectedTransport)
        )
    }

    private fun orderPlaces(draft: TripDraft, pack: DestinationPack): List<TravelPlace> {
        val matching = pack.places.filter { it.interest in draft.interests }
        val candidates = (matching + pack.places.filterNot { it in matching }).distinctBy { it.id }
        val targetCount = (draft.dayCount * draft.pace.stopsPerDay).coerceAtMost(candidates.size)
        val remaining = candidates.toMutableList()
        val result = mutableListOf<TravelPlace>()
        var cursor = pack.center
        while (remaining.isNotEmpty() && result.size < targetCount) {
            val next = remaining.minBy { cursor.distanceTo(it.coordinate) }
            result += next
            remaining -= next
            cursor = next.coordinate
        }
        return result
    }

    private fun buildDays(draft: TripDraft, orderedPlaces: List<TravelPlace>): List<ItineraryDay> {
        val perDay = draft.pace.stopsPerDay
        return (0 until draft.dayCount).map { dayIndex ->
            val stops = orderedPlaces.drop(dayIndex * perDay).take(perDay)
            ItineraryDay(dayIndex, stops, buildSchedule(dayIndex, stops, draft.pace, !draft.skipAccommodation))
        }
    }

    private fun buildSchedule(
        dayIndex: Int,
        stops: List<TravelPlace>,
        pace: TripPace,
        hasAccommodation: Boolean
    ): List<ScheduleItem> {
        val slots = when (pace) {
            TripPace.RELAXED -> listOf("10:00–12:00", "14:30–16:30")
            TripPace.BALANCED -> listOf("09:30–11:30", "13:30–15:30", "16:00–18:00")
            TripPace.FULL -> listOf("09:00–10:30", "11:00–12:30", "14:00–15:30", "16:00–17:30")
        }
        val schedule = mutableListOf<ScheduleItem>()
        stops.forEachIndexed { index, stop ->
            if (index == 1) {
                schedule += ScheduleItem(
                    id = "$dayIndex-lunch",
                    timeText = if (pace == TripPace.RELAXED) "12:00–14:30" else "12:30–13:30",
                    title = "午餐与休息",
                    detail = "在相邻地点附近用餐，给排队和临时调整留出余量"
                )
            }
            schedule += ScheduleItem(
                id = "$dayIndex-${stop.id}",
                timeText = slots[index.coerceAtMost(slots.lastIndex)],
                title = stop.name,
                detail = stop.introduction,
                placeId = stop.id
            )
        }
        if (hasAccommodation && stops.isNotEmpty()) {
            schedule += ScheduleItem(
                id = "$dayIndex-hotel",
                timeText = if (pace == TripPace.FULL) "18:30后" else "17:30后",
                title = if (dayIndex == 0) "办理入住并休息" else "回到住处",
                detail = "把晚间留白保留下来，不让旅行变成赶路"
            )
        }
        return schedule
    }

    private fun buildAccommodations(
        draft: TripDraft,
        pack: DestinationPack,
        days: List<ItineraryDay>
    ): List<AccommodationOption> {
        if (draft.skipAccommodation) return emptyList()
        val stops = days.flatMap { it.stops }
        val railHub = pack.accessPoints.firstOrNull { it.kind == LongDistanceMode.TRAIN }
        return pack.accommodations.map { seed ->
            val average = stops.map { seed.coordinate.distanceTo(it.coordinate) }.averageOrZero().roundToInt()
            val hubDistance = railHub?.coordinate?.distanceTo(seed.coordinate)?.roundToInt() ?: 0
            @Suppress("DEPRECATION")
            val encoded = URLEncoder.encode(seed.name, "UTF-8")
            AccommodationOption(
                name = seed.name,
                address = seed.address,
                coordinate = seed.coordinate,
                averageAttractionDistanceMeters = average,
                hubDistanceMeters = hubDistance,
                quotes = listOf(
                    PriceQuote("携程", unit = QuoteUnit.PER_NIGHT, kind = QuoteKind.CHECK_ON_PROVIDER, bookingURL = "https://hotels.ctrip.com/hotels/list?city=14&searchWord=$encoded", note = "选择日期与房型后核价"),
                    PriceQuote("去哪儿", unit = QuoteUnit.PER_NIGHT, kind = QuoteKind.CHECK_ON_PROVIDER, bookingURL = "https://hotel.qunar.com/", note = "选择日期与房型后核价"),
                    PriceQuote("RollingGo", unit = QuoteUnit.PER_NIGHT, kind = QuoteKind.CHECK_ON_PROVIDER, note = "配置开源报价节点后刷新")
                ),
                recommendationReasons = listOf(
                    "到已选景点平均${average.distanceText()}",
                    railHub?.let { "${it.name}到酒店${hubDistance.distanceText()}" } ?: "等待枢纽距离"
                ),
                isRecommended = false
            )
        }.sortedBy { it.averageAttractionDistanceMeters * 0.7 + it.hubDistanceMeters * 0.3 }
            .mapIndexed { index, option -> option.copy(isRecommended = index == 0) }
    }

    private fun buildTransports(
        draft: TripDraft,
        accessPoints: List<AccessPoint>,
        accommodation: AccommodationOption?
    ): List<TransportOption> {
        val trainHub = accessPoints.firstOrNull { it.kind == LongDistanceMode.TRAIN }
        val airport = accessPoints.firstOrNull { it.kind == LongDistanceMode.FLIGHT }
        val options = listOf(
            fallbackTransport(draft, LongDistanceMode.TRAIN, trainHub, accommodation, "铁路12306", "https://www.12306.cn/"),
            fallbackTransport(draft, LongDistanceMode.FLIGHT, airport, accommodation, "携程/去哪儿", "https://flights.ctrip.com/"),
            fallbackTransport(draft, LongDistanceMode.DRIVING, null, accommodation, "地图导航", "https://uri.amap.com/navigation")
        )
        return rerankTransports(draft, options, accommodation)
    }

    private fun fallbackTransport(
        draft: TripDraft,
        mode: LongDistanceMode,
        accessPoint: AccessPoint?,
        accommodation: AccommodationOption?,
        provider: String,
        bookingURL: String
    ): TransportOption {
        val transfer = if (accessPoint != null && accommodation != null) {
            accessPoint.coordinate.distanceTo(accommodation.coordinate).roundToInt()
        } else null
        val duration = when (mode) {
            LongDistanceMode.TRAIN -> 120
            LongDistanceMode.FLIGHT -> 240
            LongDistanceMode.DRIVING -> 210
        }
        val reasons = buildList {
            add("总耗时会在取得实时班次后重算")
            if (accessPoint != null && transfer != null) add("${accessPoint.name}到住宿${transfer.distanceText()}")
            if (mode == LongDistanceMode.DRIVING) add("会把停车、高速费与市内拥堵一起计算")
        }
        return TransportOption(
            mode = mode,
            title = "${mode.title} · 待实时查询",
            originName = draft.origin.ifBlank { "出发地待定" },
            destinationName = accessPoint?.name ?: draft.destination,
            departureTime = null,
            arrivalTime = null,
            durationMinutes = duration,
            arrivalAccessPoint = accessPoint,
            hotelTransferMeters = transfer,
            quotes = listOf(
                PriceQuote(provider, unit = QuoteUnit.PER_PERSON, kind = QuoteKind.CHECK_ON_PROVIDER, bookingURL = bookingURL, note = "进入渠道核对班次、价格与退改")
            ),
            recommendationReasons = reasons,
            isRecommended = false
        )
    }

    private fun rerankTransports(
        draft: TripDraft,
        options: List<TransportOption>,
        accommodation: AccommodationOption?
    ): List<TransportOption> {
        val refreshed = options.map { option ->
            val transfer = if (option.arrivalAccessPoint != null && accommodation != null) {
                option.arrivalAccessPoint.coordinate.distanceTo(accommodation.coordinate).roundToInt()
            } else option.hotelTransferMeters
            val reasons = option.recommendationReasons.filterNot { it.contains("到住宿") }.toMutableList()
            if (option.arrivalAccessPoint != null && transfer != null) {
                reasons += "${option.arrivalAccessPoint.name}到住宿${transfer.distanceText()}"
            }
            option.copy(hotelTransferMeters = transfer, recommendationReasons = reasons, isRecommended = false)
        }
        val sorted = refreshed.sortedWith(
            compareBy<TransportOption> {
                if (draft.preferredLongDistanceMode == null || it.mode == draft.preferredLongDistanceMode) 0 else 1
            }.thenBy {
                it.quotes.mapNotNull { quote -> quote.amountCNY }.minOrNull() ?: Int.MAX_VALUE
            }.thenBy {
                (it.durationMinutes ?: 9_999) + ((it.hotelTransferMeters ?: 0) / 450)
            }
        )
        return sorted.mapIndexed { index, option -> option.copy(isRecommended = index == 0) }
    }

    private fun buildExpenses(
        draft: TripDraft,
        accommodation: AccommodationOption?,
        transport: TransportOption?
    ): List<ExpenseLine> {
        val totalBudget = draft.budgetPerPerson * draft.travelers.coerceAtLeast(1)
        val rooms = ((draft.travelers + 1) / 2).coerceAtLeast(1)
        val liveHotel = accommodation?.quotes?.filter { it.kind == QuoteKind.LIVE }?.minByOrNull { it.amountCNY ?: Int.MAX_VALUE }
        val liveTransport = transport?.quotes?.filter { it.kind == QuoteKind.LIVE }?.minByOrNull { it.amountCNY ?: Int.MAX_VALUE }
        val transportAmount = liveTransport?.amountCNY?.let { amount ->
            if (liveTransport.unit == QuoteUnit.PER_PERSON) amount * draft.travelers else amount
        } ?: (totalBudget * 0.24).roundToInt()
        val hotelAmount = if (draft.skipAccommodation) 0 else liveHotel?.amountCNY?.let { amount ->
            if (liveHotel.unit == QuoteUnit.TOTAL) amount else amount * draft.nights * rooms
        } ?: (totalBudget * 0.34).roundToInt()
        return listOf(
            ExpenseLine("transport", "往返大交通", liveTransport?.let { "${it.provider} · ${it.kind.title}" } ?: "先留出总预算的24%", transportAmount, if (liveTransport != null) ExpenseSource.LIVE else ExpenseSource.BUDGET),
            ExpenseLine("hotel", "住宿", if (draft.skipAccommodation) "已跳过住宿" else liveHotel?.let { "${draft.nights}晚 × ${rooms}间 · ${it.provider}" } ?: "${draft.nights}晚 · 等待多渠道报价", hotelAmount, if (liveHotel != null) ExpenseSource.LIVE else ExpenseSource.BUDGET),
            ExpenseLine("tickets", "景点与预约", "逐项核价前的额度", (totalBudget * 0.13).roundToInt(), ExpenseSource.BUDGET),
            ExpenseLine("meals", "餐饮", "正餐、茶歇与不赶时间的余量", (totalBudget * 0.17).roundToInt(), ExpenseSource.BUDGET),
            ExpenseLine("local", "市内交通", "地铁、公交与必要打车", (totalBudget * 0.07).roundToInt(), ExpenseSource.BUDGET),
            ExpenseLine("buffer", "机动金", "价格波动与临时调整", (totalBudget * 0.05).roundToInt(), ExpenseSource.BUDGET)
        )
    }
}

private fun List<Double>.averageOrZero(): Double = if (isEmpty()) 0.0 else average()
