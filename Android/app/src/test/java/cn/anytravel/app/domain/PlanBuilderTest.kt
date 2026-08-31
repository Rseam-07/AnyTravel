package cn.anytravel.app.domain

import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripPace
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
}
