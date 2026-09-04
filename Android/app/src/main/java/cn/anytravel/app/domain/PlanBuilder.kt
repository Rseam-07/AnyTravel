package cn.anytravel.app.domain

import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.DestinationPack
import cn.anytravel.app.model.ExpenseLine
import cn.anytravel.app.model.ExpenseSource
import cn.anytravel.app.model.ItineraryDay
import cn.anytravel.app.model.LocalTravelMode
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.ScheduleItem
import cn.anytravel.app.model.TransportOption
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripInterest
import cn.anytravel.app.model.TripPace
import cn.anytravel.app.model.distanceText
import java.net.URLEncoder
import java.time.DayOfWeek
import java.time.LocalDate
import kotlin.math.roundToInt

class PlanBuilder {
    fun build(
        draft: TripDraft,
        pack: DestinationPack,
        selectedPlaceIDs: Set<String> = emptySet(),
        selectionWasSkipped: Boolean = selectedPlaceIDs.isEmpty()
    ): CompletePlan {
        val orderedPlaces = orderPlaces(draft, pack, selectedPlaceIDs)
        val days = buildDays(draft, orderedPlaces, selectedPlaceIDs, pack.center)
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
            sourceNote = pack.sourceNote,
            selectedPlaceIDs = selectedPlaceIDs.intersect(orderedPlaces.mapTo(mutableSetOf()) { it.id }),
            planningNotes = planningNotes(draft, orderedPlaces, selectedPlaceIDs, selectionWasSkipped)
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
        liveTransports: List<TransportOption>,
        discoveredAccommodations: List<AccommodationOption> = emptyList()
    ): CompletePlan {
        val quoted = plan.accommodations.map { option ->
            val live = accommodationQuotes[option.id].orEmpty()
            if (live.isEmpty()) option else option.copy(
                quotes = mergeQuotes(option.quotes, live)
            )
        }
        val accommodations = mergeAccommodations(quoted, discoveredAccommodations).sortedBy { option ->
            option.quotes.filter { it.isCurrentPrice() }.mapNotNull { it.amountCNY }.minOrNull()
                ?: Int.MAX_VALUE
        }
        val previousAccommodation = accommodations.firstOrNull { it.id == plan.selectedAccommodationId }
        val selectedAccommodationId = when {
            previousAccommodation?.quotes?.any { it.isCurrentPrice() } == true -> previousAccommodation.id
            accommodations.any { option -> option.quotes.any { it.isCurrentPrice() } } ->
                accommodations.first { option -> option.quotes.any { it.isCurrentPrice() } }.id
            previousAccommodation != null -> previousAccommodation.id
            else -> accommodations.firstOrNull()?.id
        }
        val selectedAccommodation = accommodations.firstOrNull { it.id == selectedAccommodationId }
        val transports = rerankTransports(
            plan.draft,
            mergeTransports(plan.transports, liveTransports),
            selectedAccommodation
        )
        val previousTransport = transports.firstOrNull { it.id == plan.selectedTransportId }
        val selectedTransportId = when {
            previousTransport?.quotes?.any { it.isCurrentPrice() } == true -> previousTransport.id
            previousTransport != null && transports.any {
                it.direction == previousTransport.direction && it.mode == previousTransport.mode && it.quotes.any(PriceQuote::isCurrentPrice)
            } -> transports.first {
                it.direction == previousTransport.direction && it.mode == previousTransport.mode && it.quotes.any(PriceQuote::isCurrentPrice)
            }.id
            previousTransport != null -> previousTransport.id
            else -> transports.firstOrNull {
                it.direction == cn.anytravel.app.model.TransportDirection.OUTBOUND && it.quotes.any(PriceQuote::isCurrentPrice)
            }?.id ?: transports.firstOrNull { it.direction == cn.anytravel.app.model.TransportDirection.OUTBOUND }?.id
                ?: transports.firstOrNull()?.id
        }
        val selectedTransport = transports.firstOrNull { it.id == selectedTransportId }
        return plan.copy(
            accommodations = accommodations.map { it.copy(isRecommended = it.id == selectedAccommodationId) },
            selectedAccommodationId = selectedAccommodationId,
            transports = transports,
            selectedTransportId = selectedTransportId,
            expenses = buildExpenses(plan.draft, selectedAccommodation, selectedTransport)
        )
    }

    private fun orderPlaces(
        draft: TripDraft,
        pack: DestinationPack,
        selectedPlaceIDs: Set<String>
    ): List<TravelPlace> {
        val candidates = deduplicatePlaces(pack.places)
        val selected = candidates.filter { it.id in selectedPlaceIDs }.sortedBy { it.popularityRank }
        val remainingCandidates = candidates.filterNot { it.id in selectedPlaceIDs }.sortedWith(
            compareBy<TravelPlace> { if (it.interest in draft.interests) 0 else 1 }
                .thenBy { it.popularityRank }
        )
        val targetCount = maxOf(draft.dayCount * draft.pace.stopsPerDay, selected.size)
            .coerceAtMost(candidates.size)
        val chosen = (selected + remainingCandidates.take((targetCount - selected.size).coerceAtLeast(0)))
            .distinctBy { normalizedPlaceName(it.name) }
        val selectedOrder = selected.associate { it.id to it.popularityRank }
        val weighted = chosen.sortedWith(
            compareBy<TravelPlace> { if (it.id in selectedPlaceIDs) 0 else 1 }
                .thenBy { selectedOrder[it.id] ?: it.popularityRank }
        )
        return weighted
    }

    private fun buildDays(
        draft: TripDraft,
        orderedPlaces: List<TravelPlace>,
        selectedPlaceIDs: Set<String>,
        center: cn.anytravel.app.model.Coordinate
    ): List<ItineraryDay> {
        val groups = avoidRegularClosures(
            spatiallyBalancedGroups(orderedPlaces, draft.dayCount.coerceAtLeast(1), center),
            draft
        )
        val tripStart = runCatching { LocalDate.parse(draft.startDate) }.getOrNull()
        return (0 until draft.dayCount).map { dayIndex ->
            val stops = groups.getOrNull(dayIndex).orEmpty()
            val orderedStops = orderWithinDay(stops, center)
            ItineraryDay(
                dayIndex,
                orderedStops,
                buildSchedule(
                    dayIndex = dayIndex,
                    stops = orderedStops,
                    pace = draft.pace,
                    localTravelMode = draft.localTravelMode,
                    hasAccommodation = !draft.skipAccommodation,
                    selectedPlaceIDs = selectedPlaceIDs,
                    plannedDate = tripStart?.plusDays(dayIndex.toLong())
                )
            )
        }
    }

    private fun spatiallyBalancedGroups(
        places: List<TravelPlace>,
        requestedDayCount: Int,
        center: cn.anytravel.app.model.Coordinate
    ): List<List<TravelPlace>> {
        if (places.isEmpty()) return List(requestedDayCount) { emptyList() }
        val activeDayCount = minOf(requestedDayCount, places.size)
        val base = places.size / activeDayCount
        val remainder = places.size % activeDayCount
        val capacities = (0 until activeDayCount).map { base + if (it < remainder) 1 else 0 }
        val seedPool = places.filter { it.interest != TripInterest.FOOD && it.interest != TripInterest.NIGHT }
            .ifEmpty { places }
        val seeds = mutableListOf(seedPool.minBy { it.popularityRank })
        while (seeds.size < activeDayCount) {
            val next = seedPool.filterNot { candidate -> seeds.any { it.id == candidate.id } }
                .maxByOrNull { candidate -> seeds.minOf { it.coordinate.distanceTo(candidate.coordinate) } }
                ?: break
            seeds += next
        }
        val groups = seeds.map { mutableListOf(it) }.toMutableList()
        val remaining = places.filterNot { candidate -> seeds.any { it.id == candidate.id } }
            .sortedBy { it.popularityRank }
        for (place in remaining) {
            val available = groups.indices.filter { groups[it].size < capacities[it] }.ifEmpty { groups.indices.toList() }
            val target = available.minBy { index ->
                val centroid = centroid(groups[index])
                val duplicateSpecialPenalty = when (place.interest) {
                    TripInterest.FOOD, TripInterest.NIGHT -> if (groups[index].any { it.interest == place.interest }) 20_000.0 else 0.0
                    else -> 0.0
                }
                centroid.distanceTo(place.coordinate) + duplicateSpecialPenalty
            }
            groups[target] += place
        }
        val sorted = groups.sortedBy { centroid(it).distanceTo(center) }
        return sorted + List((requestedDayCount - sorted.size).coerceAtLeast(0)) { emptyList() }
    }

    private fun orderWithinDay(
        places: List<TravelPlace>,
        center: cn.anytravel.app.model.Coordinate
    ): List<TravelPlace> {
        val ordinary = places.filter { it.interest != TripInterest.FOOD && it.interest != TripInterest.NIGHT }.toMutableList()
        val food = places.filter { it.interest == TripInterest.FOOD }.toMutableList()
        val night = places.filter { it.interest == TripInterest.NIGHT }.toMutableList()
        val result = mutableListOf<TravelPlace>()
        var cursor = if (ordinary.isEmpty()) center else centroid(ordinary)
        fun takeNearest(pool: MutableList<TravelPlace>) {
            if (pool.isEmpty()) return
            val next = pool.minBy { cursor.distanceTo(it.coordinate) }
            pool -= next
            result += next
            cursor = next.coordinate
        }
        takeNearest(ordinary)
        takeNearest(food)
        while (ordinary.isNotEmpty()) takeNearest(ordinary)
        while (food.isNotEmpty()) takeNearest(food)
        while (night.isNotEmpty()) takeNearest(night)
        return result
    }

    private fun avoidRegularClosures(groups: List<List<TravelPlace>>, draft: TripDraft): List<List<TravelPlace>> {
        val start = runCatching { LocalDate.parse(draft.startDate) }.getOrNull() ?: return groups
        val result = groups.map { it.toMutableList() }.toMutableList()
        for (dayIndex in result.indices) {
            val date = start.plusDays(dayIndex.toLong())
            for (stopIndex in result[dayIndex].indices) {
                val closed = result[dayIndex][stopIndex]
                if (!isRegularlyClosed(closed, date)) continue
                val swap = result.indices.asSequence().filter { it != dayIndex }.flatMap { otherDay ->
                    result[otherDay].indices.asSequence().map { otherStop -> otherDay to otherStop }
                }.filter { (otherDay, otherStop) ->
                    !isRegularlyClosed(closed, start.plusDays(otherDay.toLong())) &&
                        !isRegularlyClosed(result[otherDay][otherStop], date)
                }.minByOrNull { (otherDay, otherStop) ->
                    val replacement = result[otherDay][otherStop]
                    replacement.coordinate.distanceTo(centroid(result[dayIndex])) +
                        closed.coordinate.distanceTo(centroid(result[otherDay])) +
                        if (replacement.interest == closed.interest) 0.0 else 4_000.0
                }
                if (swap != null) {
                    val (otherDay, otherStop) = swap
                    result[dayIndex][stopIndex] = result[otherDay][otherStop]
                    result[otherDay][otherStop] = closed
                }
            }
        }
        return result
    }

    private fun centroid(places: List<TravelPlace>): cn.anytravel.app.model.Coordinate {
        if (places.isEmpty()) return cn.anytravel.app.model.Coordinate(0.0, 0.0)
        return cn.anytravel.app.model.Coordinate(
            places.map { it.coordinate.latitude }.average(),
            places.map { it.coordinate.longitude }.average()
        )
    }

    private fun buildSchedule(
        dayIndex: Int,
        stops: List<TravelPlace>,
        pace: TripPace,
        localTravelMode: LocalTravelMode,
        hasAccommodation: Boolean,
        selectedPlaceIDs: Set<String>,
        plannedDate: LocalDate?
    ): List<ScheduleItem> {
        val schedule = mutableListOf<ScheduleItem>()
        var minute = when (pace) {
            TripPace.RELAXED -> 9 * 60 + 45
            TripPace.BALANCED -> 9 * 60 + 15
            TripPace.FULL -> 8 * 60 + 45
        }
        var lunchAdded = false
        stops.forEachIndexed { index, stop ->
            if (index > 0) {
                val transferStart = minute
                minute += estimatedTransferMinutes(stops[index - 1], stop, localTravelMode)
                schedule += ScheduleItem(
                    id = "$dayIndex-transfer-$index",
                    timeText = timeRange(transferStart, minute),
                    title = "前往${stop.name}",
                    detail = "已留出换乘、找路与进场缓冲，实际以地图路线为准"
                )
            }
            if (stop.interest == TripInterest.FOOD && !lunchAdded) {
                minute = maxOf(minute, 11 * 60 + 30)
                lunchAdded = true
            } else if (!lunchAdded && minute >= 11 * 60 + 40) {
                val lunchStart = minute.coerceAtLeast(12 * 60)
                minute = lunchStart + if (pace == TripPace.RELAXED) 90 else 70
                schedule += ScheduleItem(
                    id = "$dayIndex-lunch",
                    timeText = timeRange(lunchStart, minute),
                    title = "午餐与休息",
                    detail = "在相邻地点附近用餐，给排队和临时调整留出余量"
                )
                lunchAdded = true
            }
            val visitStart = minute
            val paceFactor = when (pace) {
                TripPace.RELAXED -> 1.10
                TripPace.BALANCED -> 1.0
                TripPace.FULL -> 0.86
            }
            val selectedBonus = if (stop.id in selectedPlaceIDs) 30 else 0
            val visitMinutes = (((stop.suggestedVisitMinutes * paceFactor).roundToInt() + selectedBonus + 7) / 15 * 15)
                .coerceIn(60, 210)
            minute += visitMinutes
            schedule += ScheduleItem(
                id = "$dayIndex-${stop.id}",
                timeText = timeRange(visitStart, minute),
                title = stop.name,
                detail = buildString {
                    if (stop.id in selectedPlaceIDs) append("主游览点 · ")
                    append(stop.introduction)
                    append(" · 建议停留${durationText(visitMinutes)}")
                    if (stop.interest == TripInterest.FOOD && lunchAdded) append(" · 这一站兼作正餐")
                    if (plannedDate != null && isRegularlyClosed(stop, plannedDate)) append(" · 计划日为常规休息日，请复核节假日安排")
                },
                placeId = stop.id
            )
        }
        if (hasAccommodation && stops.isNotEmpty()) {
            schedule += ScheduleItem(
                id = "$dayIndex-hotel",
                timeText = "${clock(minute)}后",
                title = if (dayIndex == 0) "办理入住并休息" else "回到住处",
                detail = "把晚间留白保留下来，不让旅行变成赶路"
            )
        }
        return schedule
    }

    private fun estimatedTransferMinutes(
        from: TravelPlace,
        to: TravelPlace,
        mode: LocalTravelMode
    ): Int {
        val kilometres = from.coordinate.distanceTo(to.coordinate) / 1_000.0
        val (speed, overhead) = when (mode) {
            LocalTravelMode.WALKING -> 4.5 to 4.0
            LocalTravelMode.TRANSIT -> 18.0 to 12.0
            LocalTravelMode.DRIVING -> 27.0 to 9.0
        }
        return ((kilometres / speed * 60 + overhead) / 5).roundToInt().coerceIn(1, 24) * 5
    }

    private fun isRegularlyClosed(place: TravelPlace, date: LocalDate): Boolean {
        if (date.dayOfWeek == DayOfWeek.MONDAY && listOf("故宫博物院", "中国国家博物馆", "国家博物馆", "苏州博物馆").any(place.name::contains)) {
            return true
        }
        val weekly = place.openingHoursWeek ?: return false
        val token = when (date.dayOfWeek) {
            DayOfWeek.MONDAY -> "Mo"
            DayOfWeek.TUESDAY -> "Tu"
            DayOfWeek.WEDNESDAY -> "We"
            DayOfWeek.THURSDAY -> "Th"
            DayOfWeek.FRIDAY -> "Fr"
            DayOfWeek.SATURDAY -> "Sa"
            DayOfWeek.SUNDAY -> "Su"
        }
        return weekly.split(';', '；').any { segment ->
            segment.contains(token, ignoreCase = true) && Regex("off|closed|闭馆|休息", RegexOption.IGNORE_CASE).containsMatchIn(segment)
        }
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
                if (it.direction == cn.anytravel.app.model.TransportDirection.OUTBOUND) 0 else 1
            }.thenBy {
                if (draft.preferredLongDistanceMode == null || it.mode == draft.preferredLongDistanceMode) 0 else 1
            }.thenBy {
                if (it.quotes.any { quote -> quote.isCurrentPrice() }) 0 else 1
            }.thenBy {
                it.quotes.filter { quote -> quote.isCurrentPrice() }.mapNotNull { quote -> quote.amountCNY }.minOrNull()
                    ?: Int.MAX_VALUE
            }.thenBy {
                (it.durationMinutes ?: 9_999) + ((it.hotelTransferMeters ?: 0) / 450)
            }
        )
        return sorted.mapIndexed { index, option -> option.copy(isRecommended = index == 0) }
    }

    private fun deduplicatePlaces(places: List<TravelPlace>): List<TravelPlace> {
        val result = mutableListOf<TravelPlace>()
        for (place in places.sortedBy { it.popularityRank }) {
            val normalized = normalizedPlaceName(place.name)
            val index = result.indexOfFirst { existing ->
                normalizedPlaceName(existing.name) == normalized ||
                    (existing.interest == place.interest && existing.coordinate.distanceTo(place.coordinate) <= 90)
            }
            if (index < 0) {
                result += place
            } else {
                val existing = result[index]
                result[index] = if (place.popularityRank < existing.popularityRank) place else existing
            }
        }
        return result
    }

    private fun mergeQuotes(existing: List<PriceQuote>, incoming: List<PriceQuote>): List<PriceQuote> {
        val merged = linkedMapOf<String, PriceQuote>()
        (existing + incoming).forEach { quote ->
            val key = "${quote.provider.lowercase()}|${quote.unit}"
            val current = merged[key]
            val quoteScore = quoteScore(quote)
            if (current == null || quoteScore < quoteScore(current)) merged[key] = quote
        }
        return merged.values.sortedWith(
            compareBy<PriceQuote> { if (it.isCurrentPrice()) 0 else 1 }
                .thenBy { it.amountCNY ?: Int.MAX_VALUE }
        )
    }

    private fun mergeTransports(
        existing: List<TransportOption>,
        incoming: List<TransportOption>
    ): List<TransportOption> {
        if (incoming.isEmpty()) return existing
        val result = existing.toMutableList()
        for (option in incoming) {
            val index = result.indexOfFirst { current -> sameTransport(current, option) }
            if (index < 0) {
                result += option
            } else {
                val current = result[index]
                val richer = if (transportCompleteness(option) >= transportCompleteness(current)) option else current
                result[index] = richer.copy(
                    id = current.id,
                    arrivalAccessPoint = option.arrivalAccessPoint ?: current.arrivalAccessPoint,
                    hotelTransferMeters = option.hotelTransferMeters ?: current.hotelTransferMeters,
                    quotes = mergeQuotes(current.quotes, option.quotes),
                    recommendationReasons = (current.recommendationReasons + option.recommendationReasons)
                        .distinct().take(5),
                    isRecommended = current.isRecommended || option.isRecommended
                )
            }
        }
        val liveKeys = incoming.filter(::hasCurrentPrice)
            .map { it.mode to it.direction }.toSet()
        return result.filterNot { option ->
            isTransportPlaceholder(option) && (option.mode to option.direction) in liveKeys
        }.distinctBy { option ->
            "${option.mode}|${option.direction}|${transportServiceNumber(option)}|${option.departureTime.orEmpty()}"
        }
    }

    private fun sameTransport(lhs: TransportOption, rhs: TransportOption): Boolean {
        if (lhs.mode != rhs.mode || lhs.direction != rhs.direction) return false
        val lhsService = transportServiceNumber(lhs)
        val rhsService = transportServiceNumber(rhs)
        if (lhsService.isNotBlank() && rhsService.isNotBlank() && lhsService == rhsService) {
            return lhs.departureTime == null || rhs.departureTime == null || lhs.departureTime == rhs.departureTime
        }
        return normalizedTransportPlace(lhs.originName) == normalizedTransportPlace(rhs.originName) &&
            normalizedTransportPlace(lhs.destinationName) == normalizedTransportPlace(rhs.destinationName) &&
            lhs.departureTime != null && lhs.departureTime == rhs.departureTime
    }

    private fun transportServiceNumber(option: TransportOption): String =
        Regex("(?i)\\b(?:[A-Z]{1,3}\\s?\\d{1,5}|\\d{2,4})\\b")
            .find(option.title)?.value?.replace(" ", "")?.uppercase().orEmpty()

    private fun normalizedTransportPlace(value: String): String = value.lowercase()
        .replace(Regex("机场|火车站|高铁站|站|航站楼|t\\d+|\\s"), "")

    private fun isTransportPlaceholder(option: TransportOption): Boolean =
        option.title.contains("待实时查询") ||
            !hasCurrentPrice(option)

    private fun hasCurrentPrice(option: TransportOption): Boolean =
        option.quotes.any { it.isCurrentPrice() }

    private fun transportCompleteness(option: TransportOption): Int =
        listOf(option.departureTime, option.arrivalTime).count { !it.isNullOrBlank() } * 2 +
            (if (option.durationMinutes != null) 1 else 0) +
            (if (hasCurrentPrice(option)) 3 else 0)

    private fun quoteScore(quote: PriceQuote): Long {
        val kind = when (quote.kind) {
            QuoteKind.LIVE -> 0L
            QuoteKind.INDICATIVE -> 1L
            QuoteKind.CHECK_ON_PROVIDER -> 2L
            QuoteKind.BUDGET_ENVELOPE -> 3L
        }
        return kind * 1_000_000L + (quote.amountCNY ?: 999_999)
    }

    private fun mergeAccommodations(
        existing: List<AccommodationOption>,
        incoming: List<AccommodationOption>
    ): List<AccommodationOption> {
        val result = existing.toMutableList()
        for (option in incoming) {
            val normalized = normalizedHotelName(option.name)
            val index = result.indexOfFirst { current ->
                val currentName = normalizedHotelName(current.name)
                currentName == normalized ||
                    (currentName.length >= 4 && normalized.length >= 4 &&
                        (currentName.contains(normalized) || normalized.contains(currentName))) ||
                    (current.coordinate.distanceTo(option.coordinate) <= 100 &&
                        currentName.take(4) == normalized.take(4))
            }
            if (index < 0) {
                result += option
            } else {
                val current = result[index]
                result[index] = current.copy(
                    address = option.address.ifBlank { current.address },
                    coordinate = option.coordinate,
                    averageAttractionDistanceMeters = minOf(
                        current.averageAttractionDistanceMeters,
                        option.averageAttractionDistanceMeters
                    ),
                    hubDistanceMeters = minOf(current.hubDistanceMeters, option.hubDistanceMeters),
                    quotes = mergeQuotes(current.quotes, option.quotes),
                    recommendationReasons = (current.recommendationReasons + option.recommendationReasons).distinct().take(4),
                    brand = option.brand ?: current.brand,
                    starRating = option.starRating ?: current.starRating,
                    guestRating = option.guestRating ?: current.guestRating,
                    imageURL = option.imageURL ?: current.imageURL,
                    amenities = (current.amenities + option.amenities).distinct().take(12),
                    tags = (current.tags + option.tags).distinct().take(10),
                    sources = (current.sources + option.sources).distinct()
                )
            }
        }
        val hasRealHotel = result.any { it.name != "住宿位置待选择" && it.quotes.any { quote -> quote.isCurrentPrice() } }
        return if (hasRealHotel) result.filterNot { it.name == "住宿位置待选择" } else result
    }

    private fun planningNotes(
        draft: TripDraft,
        places: List<TravelPlace>,
        selectedPlaceIDs: Set<String>,
        selectionWasSkipped: Boolean
    ): List<String> = buildList {
        if (selectionWasSkipped) {
            add("你跳过了景点勾选，已按热度、兴趣与距离补齐一份默认轻松路线。")
        } else if (selectedPlaceIDs.size < draft.dayCount) {
            add("你选的主游览点较少，已按热门程度补入相邻地点；主游览点会留出更长时间。")
        } else {
            add("已优先保留你勾选的${selectedPlaceIDs.size}处，并让主游览点拥有更完整的停留时间。")
        }
        val comfortableCapacity = draft.dayCount * TripPace.RELAXED.stopsPerDay
        if (selectedPlaceIDs.size > comfortableCapacity || places.size > draft.dayCount * draft.pace.stopsPerDay) {
            add("点位偏多，当前方案可能有行程压力；可减少景点或延长天数。")
        }
        add("每天包含移动、进场与用餐余量，同名或相距过近的重复地点已合并。")
    }

    private fun normalizedPlaceName(value: String): String = value.lowercase()
        .replace("风景名胜区", "")
        .replace("历史文化街区", "")
        .replace("博物馆", "")
        .replace("景区", "")
        .replace("公园", "")
        .replace(Regex("[\\s()（）·—_-]"), "")

    private fun normalizedHotelName(value: String): String = value.lowercase()
        .replace("国际大酒店", "")
        .replace("精品酒店", "")
        .replace("度假酒店", "")
        .replace("酒店", "")
        .replace("宾馆", "")
        .replace("民宿", "")
        .replace(Regex("[\\s()（）·—_-]"), "")

    private fun timeRange(start: Int, end: Int): String = "${clock(start)}–${clock(end)}"

    private fun clock(minutes: Int): String {
        val normalized = minutes.coerceAtLeast(0)
        return "%02d:%02d".format(normalized / 60, normalized % 60)
    }

    private fun durationText(minutes: Int): String = when {
        minutes < 60 -> "${minutes}分钟"
        minutes % 60 == 0 -> "${minutes / 60}小时"
        else -> "${minutes / 60}小时${minutes % 60}分钟"
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

private fun PriceQuote.isCurrentPrice(): Boolean =
    amountCNY != null && (kind == QuoteKind.LIVE || kind == QuoteKind.INDICATIVE)

private fun List<Double>.averageOrZero(): Double = if (isEmpty()) 0.0 else average()
