package cn.anytravel.app.data

import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.ItineraryDay
import cn.anytravel.app.model.ScheduleItem
import cn.anytravel.app.model.TravelPlace
import cn.anytravel.app.model.TripDraft
import cn.anytravel.app.model.TripInterest
import java.time.Instant
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanExportServiceTest {
    @Test
    fun calendarContainsDatedEventsAndEscapesUserText() {
        val place = TravelPlace(
            id = "garden",
            name = "拙政园,东园",
            address = "苏州;姑苏区",
            coordinate = Coordinate(31.324, 120.629),
            interest = TripInterest.GARDENS,
            introduction = "慢慢走",
            source = "test"
        )
        val plan = CompletePlan(
            id = "trip-1",
            draft = TripDraft(destination = "苏州", startDate = "2026-09-09", dayCount = 1),
            destinationCenter = Coordinate(31.3, 120.6),
            days = listOf(
                ItineraryDay(
                    index = 0,
                    stops = listOf(place),
                    schedule = listOf(
                        ScheduleItem("visit", "09:45 – 11:15", place.name, "园林;留白", place.id)
                    )
                )
            ),
            accommodations = emptyList(),
            selectedAccommodationId = null,
            transports = emptyList(),
            selectedTransportId = null,
            expenses = emptyList(),
            sourceNote = "test"
        )

        val value = PlanExportService.calendarText(plan, Instant.parse("2026-09-05T00:00:00Z"))

        assertTrue(value.contains("DTSTART;TZID=Asia/Shanghai:20260909T094500"))
        assertTrue(value.contains("DTEND;TZID=Asia/Shanghai:20260909T111500"))
        assertTrue(value.contains("SUMMARY:拙政园\\,东园"))
        assertTrue(value.contains("LOCATION:苏州\\;姑苏区"))
        assertFalse(value.contains("BEGIN:VEVENT\n"))
    }
}
