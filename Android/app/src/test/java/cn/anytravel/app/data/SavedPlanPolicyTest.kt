package cn.anytravel.app.data

import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.TripDraft
import org.junit.Assert.assertEquals
import org.junit.Test

class SavedPlanPolicyTest {
    private fun plan(title: String) = CompletePlan(
        draft = TripDraft(destination = title),
        destinationCenter = Coordinate(31.0, 120.0),
        days = emptyList(),
        accommodations = emptyList(),
        selectedAccommodationId = null,
        transports = emptyList(),
        selectedTransportId = null,
        expenses = emptyList(),
        sourceNote = "test"
    )

    @Test
    fun keepsMoreThanTwelveTripsWithoutSilentEviction() {
        val existing = (1..20).map { plan("城市$it") }
        val added = plan("新旅程")

        val result = mergeSavedPlan(added, existing)

        assertEquals(21, result.size)
        assertEquals(added.id, result.first().id)
        assertEquals(existing.map { it.id }.toSet(), result.drop(1).map { it.id }.toSet())
    }

    @Test
    fun replacesAnExistingTripWithoutCreatingADuplicate() {
        val old = plan("苏州")
        val updated = old.copy(draft = old.draft.copy(dayCount = 5))

        val result = mergeSavedPlan(updated, listOf(old, plan("杭州")))

        assertEquals(2, result.size)
        assertEquals(5, result.first().draft.dayCount)
        assertEquals(1, result.count { it.id == old.id })
    }
}
