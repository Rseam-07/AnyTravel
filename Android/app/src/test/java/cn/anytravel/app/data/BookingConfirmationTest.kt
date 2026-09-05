package cn.anytravel.app.data

import cn.anytravel.app.model.BookingConfirmation
import cn.anytravel.app.model.BookingKind
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.TripDraft
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BookingConfirmationTest {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private fun plan(confirmations: List<BookingConfirmation> = emptyList()) = CompletePlan(
        draft = TripDraft(destination = "苏州", startDate = "2026-09-10", dayCount = 3),
        destinationCenter = Coordinate(31.3, 120.6),
        days = emptyList(),
        accommodations = emptyList(),
        selectedAccommodationId = null,
        transports = emptyList(),
        selectedTransportId = null,
        expenses = emptyList(),
        sourceNote = "test",
        bookingConfirmations = confirmations
    )

    @Test
    fun confirmationRoundTripsWithNonSensitiveOrderNote() {
        val source = plan(listOf(BookingConfirmation(
            id = "booking-1",
            kind = BookingKind.ACCOMMODATION,
            itemId = "hotel-1",
            title = "测试酒店",
            confirmedAt = "2026-09-05T00:00:00Z",
            startDate = "2026-09-10",
            endDate = "2026-09-12",
            note = "订单尾号 1234"
        )))

        val restored = json.decodeFromString(CompletePlan.serializer(), json.encodeToString(CompletePlan.serializer(), source))

        assertEquals("订单尾号 1234", restored.bookingConfirmations.single().note)
        assertEquals("2026-09-12", restored.bookingConfirmations.single().endDate)
    }

    @Test
    fun olderSavedPlanWithoutConfirmationFieldStillLoads() {
        val oldPayload = json.encodeToString(CompletePlan.serializer(), plan())
            .replace(Regex(",?\"bookingConfirmations\":\\[\\]"), "")

        val restored = json.decodeFromString(CompletePlan.serializer(), oldPayload)

        assertTrue(restored.bookingConfirmations.isEmpty())
    }
}
