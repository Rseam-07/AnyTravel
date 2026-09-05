package cn.anytravel.app.data

import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.Coordinate
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind
import cn.anytravel.app.model.QuoteUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AccommodationMergerTest {
    @Test
    fun sameNearbyPropertyKeepsAllConcreteChannelQuotesAndDropsPlaceholder() {
        val rollingGo = hotel(
            id = "rollinggo-1",
            name = "苏州诺富特酒店",
            coordinate = Coordinate(31.3000, 120.6000),
            quotes = listOf(quote("RollingGo", 520), quote("住宿官网", null))
        )
        val official = hotel(
            id = "accor-1",
            name = "苏州诺富特",
            coordinate = Coordinate(31.3001, 120.6001),
            quotes = listOf(quote("住宿官网", 499)),
            officialURL = "https://all.accor.com/example"
        )

        val result = AccommodationMerger.merge(listOf(rollingGo, official))

        assertEquals(1, result.size)
        assertEquals(listOf(499, 520), result.single().quotes.mapNotNull { it.amountCNY })
        assertEquals("https://all.accor.com/example", result.single().officialWebsiteURL)
        assertEquals(setOf("RollingGo", "雅高集团官网"), result.single().sources.toSet())
    }

    @Test
    fun sameNameFarAwayRemainsASeparateBranch() {
        val first = hotel("1", "城市便捷酒店", Coordinate(31.20, 120.50), listOf(quote("A", 300)))
        val second = hotel("2", "城市便捷酒店", Coordinate(31.30, 120.70), listOf(quote("B", 280)))

        val result = AccommodationMerger.merge(listOf(first, second))

        assertEquals(2, result.size)
    }

    @Test
    fun differentBrandsInTheSameBuildingDoNotMergeByCoordinateAlone() {
        val first = hotel("1", "城市之光酒店", Coordinate(31.3000, 120.6000), listOf(quote("A", 300)))
        val second = hotel("2", "河畔精选酒店", Coordinate(31.30001, 120.60001), listOf(quote("B", 280)))

        val result = AccommodationMerger.merge(listOf(first, second))

        assertEquals(2, result.size)
    }

    @Test
    fun officialWebsiteReturnsOnlyKnownBrandFamilies() {
        assertTrue(AccommodationMerger.officialWebsite("苏州康莱德酒店", null)?.contains("hilton") == true)
        assertNull(AccommodationMerger.officialWebsite("河畔小院", null))
    }

    @Test
    fun nearbyBilingualAliasesFromTheSameBrandMerge() {
        val first = hotel("1", "苏州诺富特酒店", Coordinate(31.30, 120.60), listOf(quote("A", 500)))
        val second = hotel("2", "Novotel Suzhou", Coordinate(31.3001, 120.6001), listOf(quote("B", 490)))

        assertEquals(1, AccommodationMerger.merge(listOf(first, second)).size)
    }

    @Test
    fun nearbySisterBrandsRemainSeparate() {
        listOf(
            Triple("苏州诺富特酒店", "苏州美居酒店", "雅高"),
            Triple("苏州希尔顿酒店", "苏州希尔顿花园酒店", "Hilton"),
            Triple("苏州皇冠假日酒店", "苏州假日酒店", "IHG")
        ).forEach { (firstName, secondName, group) ->
            val first = hotel("1", firstName, Coordinate(31.30, 120.60), listOf(quote("A", 500))).copy(brand = group)
            val second = hotel("2", secondName, Coordinate(31.30001, 120.60001), listOf(quote("B", 490))).copy(brand = group)

            assertEquals("$firstName and $secondName are different brands", 2, AccommodationMerger.merge(listOf(first, second)).size)
        }
    }

    @Test
    fun emptyNormalizedNamesAreNotIdentityEvidence() {
        val first = hotel("1", "酒店", Coordinate(31.30, 120.60), listOf(quote("A", 300)))
        val second = hotel("2", "宾馆", Coordinate(31.30, 120.60), listOf(quote("B", 280)))

        assertEquals(2, AccommodationMerger.merge(listOf(first, second)).size)
    }

    private fun quote(provider: String, amount: Int?) = PriceQuote(
        provider = provider,
        amountCNY = amount,
        unit = QuoteUnit.PER_NIGHT,
        kind = if (amount == null) QuoteKind.CHECK_ON_PROVIDER else QuoteKind.LIVE,
        capturedAt = "2026-09-05T00:00:00Z",
        bookingURL = amount?.let { "https://example.com/$provider" },
        note = "测试"
    )

    private fun hotel(
        id: String,
        name: String,
        coordinate: Coordinate,
        quotes: List<PriceQuote>,
        officialURL: String? = null
    ) = AccommodationOption(
        id = id,
        name = name,
        address = "苏州",
        coordinate = coordinate,
        averageAttractionDistanceMeters = 1_000,
        hubDistanceMeters = 2_000,
        quotes = quotes,
        recommendationReasons = emptyList(),
        isRecommended = false,
        brand = if ("诺富特" in name) "雅高" else null,
        officialWebsiteURL = officialURL,
        sources = if (id.startsWith("accor")) listOf("雅高集团官网") else listOf("RollingGo")
    )
}
