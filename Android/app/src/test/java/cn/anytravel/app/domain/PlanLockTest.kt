package cn.anytravel.app.domain

import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.ItineraryDay
import cn.anytravel.app.model.LockedVisit
import cn.anytravel.app.model.PlanLockState
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import cn.anytravel.app.model.ScheduleItem
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripInterest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanLockTest {
    private val builder = PlanBuilder()
    private val center = Coordinate(31.3, 120.6)

    private fun place(id: String, name: String, latitude: Double) = TravelPlace(
        id = id,
        name = name,
        address = name,
        coordinate = Coordinate(latitude, 120.6),
        interest = TripInterest.GARDENS,
        introduction = name,
        source = "test"
    )

    private fun day(index: Int, vararg places: TravelPlace) = ItineraryDay(
        index = index,
        stops = places.toList(),
        schedule = places.mapIndexed { itemIndex, place ->
            ScheduleItem("$index-$itemIndex", if (itemIndex == 0) "10:00–11:30" else "12:00–13:30", place.name, "游览", place.id)
        }
    )

    private fun plan(days: List<ItineraryDay>, locks: PlanLockState = PlanLockState(), accommodations: List<AccommodationOption> = emptyList(), selectedAccommodationId: String? = null) = CompletePlan(
        draft = TripDraft(dayCount = days.size),
        destinationCenter = center,
        days = days,
        accommodations = accommodations,
        selectedAccommodationId = selectedAccommodationId,
        transports = emptyList(),
        selectedTransportId = null,
        expenses = emptyList(),
        sourceNote = "test",
        locks = locks
    )

    private fun stay(id: String, kind: QuoteKind) = AccommodationOption(
        id = id,
        name = id,
        address = id,
        coordinate = center,
        averageAttractionDistanceMeters = 100,
        hubDistanceMeters = 100,
        quotes = listOf(PriceQuote("test", if (kind == QuoteKind.LIVE) 500 else null, QuoteUnit.PER_NIGHT, kind, note = "test")),
        recommendationReasons = emptyList(),
        isRecommended = false
    )

    @Test
    fun lockedVisitKeepsDayOrderAndTime() {
        val a = place("a", "拙政园", 31.31)
        val b = place("b", "苏州博物馆", 31.32)
        val c = place("c", "虎丘", 31.33)
        val previous = plan(
            listOf(day(0, a, b), day(1, c)),
            PlanLockState(visits = listOf(LockedVisit("b", "苏州博物馆", 0, 1, "12:00–13:30")))
        )
        val result = builder.applyLocks(plan(listOf(day(0, c), day(1, a, b))), previous)
        assertEquals("b", result.days[0].stops[1].id)
        assertEquals("12:00–13:30", result.days[0].schedule.first { it.placeId == "b" }.timeText)
        assertEquals(1, result.days.flatMap { it.stops }.count { it.id == "b" })
    }

    @Test
    fun liveRefreshDoesNotReplaceTheChosenHotel() {
        val chosen = stay("chosen", QuoteKind.CHECK_ON_PROVIDER)
        val fresh = stay("fresh", QuoteKind.LIVE)
        val source = plan(listOf(day(0, place("a", "拙政园", 31.31))), accommodations = listOf(chosen), selectedAccommodationId = chosen.id)
        val result = builder.mergeLiveData(source, emptyMap(), emptyList(), listOf(fresh))
        assertEquals("chosen", result.selectedAccommodationId)
        assertTrue(result.accommodations.any { it.id == "fresh" })
    }
}
