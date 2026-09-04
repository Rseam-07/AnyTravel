package cn.anytravel.app.data

import cn.anytravel.app.model.AccessPoint
import cn.anytravel.app.model.CompletePlan
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.LongDistanceMode
import cn.anytravel.app.model.TripDraft
import java.time.LocalDate
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class DirectPricingClientLiveTest {
    @Test
    fun publicSourcesReturnHotelFlightAndRailPrices() = runBlocking {
        assumeTrue(System.getenv("ANYTRAVEL_RUN_LIVE_TESTS") == "1")
        val draft = TripDraft(
            origin = "上海",
            destination = "北京",
            startDate = LocalDate.now().plusDays(10).toString(),
            dayCount = 3,
            travelers = 2
        )
        val plan = CompletePlan(
            draft = draft,
            destinationCenter = Coordinate(39.9042, 116.4074),
            days = emptyList(),
            accommodations = emptyList(),
            selectedAccommodationId = null,
            transports = emptyList(),
            selectedTransportId = null,
            expenses = emptyList(),
            sourceNote = "live smoke"
        )
        val accessPoints = listOf(
            AccessPoint("北京南站", LongDistanceMode.TRAIN, Coordinate(39.8652, 116.3789)),
            AccessPoint("北京首都国际机场", LongDistanceMode.FLIGHT, Coordinate(40.0799, 116.6031))
        )

        val result = DirectPricingClient().refresh(plan, accessPoints)

        val diagnostic = buildString {
            append(result.message)
            append(" | hotels=").append(result.discoveredAccommodations.size)
            append(" | trains=").append(result.transports.count { it.mode == LongDistanceMode.TRAIN })
            append(" | flights=").append(result.transports.count { it.mode == LongDistanceMode.FLIGHT })
        }
        assertTrue(diagnostic, result.discoveredAccommodations.any { hotel -> hotel.quotes.any { it.amountCNY != null } })
        assertTrue(diagnostic, result.transports.any { it.mode == LongDistanceMode.TRAIN && it.departureTime != null && it.quotes.any { quote -> quote.amountCNY != null } })
        assertTrue(diagnostic, result.transports.any { it.mode == LongDistanceMode.FLIGHT && it.departureTime != null && it.quotes.any { quote -> quote.amountCNY != null } })
    }
}
