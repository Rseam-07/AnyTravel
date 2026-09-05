package cn.anytravel.app.model

import org.junit.Assert.assertEquals
import org.junit.Test

class TripDraftPartyTest {
    @Test
    fun legacyDraftDerivesAdultsAndRooms() {
        val draft = TripDraft(travelers = 4)
        assertEquals(4, draft.effectiveAdults)
        assertEquals(2, draft.effectiveRooms)
    }

    @Test
    fun familyPartyKeepsChildrenAgesAndTotal() {
        val draft = TripDraft(travelers = 4, adults = 2, childrenAges = listOf(5, 12), rooms = 2, seniorTravelers = 1)
        assertEquals(2, draft.effectiveAdults)
        assertEquals(2, draft.effectiveChildrenAges.size)
        assertEquals(4, draft.effectiveTotalTravelers)
        assertEquals(2, draft.effectiveRooms)
        assertEquals(1, draft.effectiveSeniorTravelers)
    }
}
