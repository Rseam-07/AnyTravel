package cn.anytravel.app.domain

import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripPace
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.TransportDirection
import cn.anytravel.app.model.TransportOption
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanBuilderTest {
    private val builder = PlanBuilder()
    private val suzhou = requireNotNull(DestinationCatalog.find("苏州"))

    @Test
    fun relaxedPlanKeepsTwoMainStopsAndLunchBuffer() {
        val plan = builder.build(TripDraft(destination = "苏州", pace = TripPace.RELAXED), suzhou)

        assertTrue(plan.days.all { it.stops.size <= 2 })
        assertTrue(plan.days.flatMap { it.schedule }.any { it.title == "午餐与休息" })
        assertTrue(plan.days.flatMap { it.schedule }.any { it.title == "办理入住并休息" })
    }

    @Test
    fun changingHotelRecalculatesArrivalTransfer() {
        val plan = builder.build(TripDraft(destination = "苏州"), suzhou)
        val alternative = plan.accommodations.last()
        val before = plan.selectedTransport?.hotelTransferMeters

        val updated = builder.selectAccommodation(plan, alternative.id)

        assertEquals(alternative.id, updated.selectedAccommodationId)
        assertNotEquals(before, updated.selectedTransport?.hotelTransferMeters)
        assertTrue(updated.accommodations.single { it.id == alternative.id }.isRecommended)
    }

    @Test
    fun budgetEnvelopeExplainsTheWholeUserBudgetBeforeLiveQuotes() {
        val draft = TripDraft(destination = "苏州", budgetPerPerson = 3_000, travelers = 2)
        val plan = builder.build(draft, suzhou)

        assertEquals(6_000, plan.totalExpense)
        assertTrue(plan.expenses.all { it.detail.isNotBlank() })
    }

    @Test
    fun dayTripRemovesAccommodationWithoutDroppingItinerary() {
        val plan = builder.build(TripDraft(destination = "苏州", dayCount = 1, skipAccommodation = true), suzhou)

        assertTrue(plan.accommodations.isEmpty())
        assertEquals(0, plan.expenses.single { it.id == "hotel" }.amountCNY)
        assertTrue(plan.days.single().stops.isNotEmpty())
    }

    @Test
    fun liveTransportReplacesPlaceholderAndMergesSameServiceQuotes() {
        val plan = builder.build(TripDraft(origin = "上海", destination = "苏州"), suzhou)
        val service = TransportOption(
            mode = LongDistanceMode.TRAIN,
            title = "G7012 · 上海→苏州",
            originName = "上海站",
            destinationName = "苏州站",
            departureTime = "09:10",
            arrivalTime = "09:42",
            durationMinutes = 32,
            arrivalAccessPoint = suzhou.accessPoints.first { it.kind == LongDistanceMode.TRAIN },
            hotelTransferMeters = null,
            quotes = listOf(PriceQuote("铁路12306", 45, QuoteUnit.PER_PERSON, QuoteKind.LIVE, note = "二等座")),
            recommendationReasons = listOf("二等座有票"),
            isRecommended = false,
            direction = TransportDirection.OUTBOUND
        )
        val secondSource = service.copy(
            id = "second-source",
            quotes = listOf(PriceQuote("去哪儿", 47, QuoteUnit.PER_PERSON, QuoteKind.LIVE, note = "当前报价"))
        )

        val firstMerge = builder.mergeLiveData(plan, emptyMap(), listOf(service))
        val merged = builder.mergeLiveData(firstMerge, emptyMap(), listOf(secondSource))

        val train = merged.transports.single { it.title.contains("G7012") }
        assertEquals(setOf("铁路12306", "去哪儿"), train.quotes.map { it.provider }.toSet())
        assertTrue(merged.transports.none { it.mode == LongDistanceMode.TRAIN && it.title.contains("待实时查询") })
    }

    @Test
    fun liveFlightReplacesCheaperBudgetPlaceholderAndBecomesVisibleSelection() {
        val base = builder.build(TripDraft(origin = "宁波", destination = "天津"), suzhou)
        val budgetPlaceholder = TransportOption(
            mode = LongDistanceMode.FLIGHT,
            title = "航班抵达天津",
            originName = "宁波",
            destinationName = "天津",
            departureTime = null,
            arrivalTime = null,
            durationMinutes = 180,
            arrivalAccessPoint = null,
            hotelTransferMeters = null,
            quotes = listOf(
                PriceQuote("AnyTravel", 320, QuoteUnit.PER_PERSON, QuoteKind.BUDGET_ENVELOPE, note = "预算预留")
            ),
            recommendationReasons = listOf("预算占位"),
            isRecommended = true,
            direction = TransportDirection.OUTBOUND
        )
        val liveFlight = TransportOption(
            mode = LongDistanceMode.FLIGHT,
            title = "厦门航空 MF8123",
            originName = "宁波栎社T2",
            destinationName = "天津滨海T2",
            departureTime = "09:10",
            arrivalTime = "11:35",
            durationMinutes = 145,
            arrivalAccessPoint = null,
            hotelTransferMeters = null,
            quotes = listOf(
                PriceQuote("飞猪", 560, QuoteUnit.PER_PERSON, QuoteKind.LIVE, note = "当前搜索起价")
            ),
            recommendationReasons = listOf("当前航班"),
            isRecommended = false,
            direction = TransportDirection.OUTBOUND
        )
        val withPlaceholder = base.copy(
            transports = listOf(budgetPlaceholder),
            selectedTransportId = budgetPlaceholder.id
        )

        val merged = builder.mergeLiveData(withPlaceholder, emptyMap(), listOf(liveFlight))

        assertTrue(merged.transports.none { it.id == budgetPlaceholder.id })
        assertEquals(liveFlight.id, merged.selectedTransportId)
        assertEquals("厦门航空 MF8123", merged.transports.first().title)
    }
}
