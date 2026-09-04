package cn.anytravel.app.data

import cn.anytravel.app.model.Coordinate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenRouteClientTest {
    @Test
    fun `decodes a real valhalla polyline6 response`() {
        val coordinates = decodePolyline6(
            "gd{vz@kvnaeFAG_AmPwAmS[iF?_AAcAlFSxm@_DF?`@At@Cfi@sBvScD`mA{QjC]lIoAvg@eFju@_MLCxB[~l@qJf]{EdH_A{I}j@"
        )

        assertTrue(coordinates.size >= 20)
        assertTrue(kotlin.math.abs(coordinates.first().latitude - 31.324167) < 0.002)
        assertTrue(kotlin.math.abs(coordinates.first().longitude - 120.627080) < 0.002)
        assertTrue(kotlin.math.abs(coordinates.last().latitude - 31.3181) < 0.002)
        assertTrue(kotlin.math.abs(coordinates.last().longitude - 120.6298) < 0.002)
    }

    @Test
    fun `rejects an incomplete shape instead of drawing corrupt geometry`() {
        assertEquals(emptyList<Coordinate>(), decodePolyline6("_"))
    }
}
