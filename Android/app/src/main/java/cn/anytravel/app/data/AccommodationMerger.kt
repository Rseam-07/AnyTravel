package cn.anytravel.app.data

import cn.anytravel.app.model.AccommodationOption
import cn.anytravel.app.model.PriceQuote
import cn.anytravel.app.model.QuoteKind

/** Canonical hotel identity and quote merging used by every Android price source. */
internal object AccommodationMerger {
    fun merge(options: List<AccommodationOption>): List<AccommodationOption> {
        val result = mutableListOf<AccommodationOption>()
        options.forEach { incoming ->
            val index = result.indexOfFirst { current -> sameProperty(current, incoming) }
            if (index < 0) {
                result += incoming.copy(quotes = mergeQuotes(emptyList(), incoming.quotes))
            } else {
                result[index] = mergePair(result[index], incoming)
            }
        }
        return result
    }

    fun normalizedName(value: String): String = value
        .lowercase()
        .replace(NAME_SEPARATORS, "")
        .replace("酒店", "")
        .replace("宾馆", "")
        .replace("民宿", "")
        .replace("旅馆", "")

    fun namesLikelyMatch(lhs: String, rhs: String): Boolean {
        val left = normalizedName(lhs)
        val right = normalizedName(rhs)
        if (left.isEmpty() || right.isEmpty()) return false
        if (left == right) return true
        return minOf(left.length, right.length) >= 4 && (left.contains(right) || right.contains(left))
    }

    fun officialWebsite(name: String, brand: String?): String? {
        val value = "$name ${brand.orEmpty()}".lowercase()
        return OFFICIAL_SITES.firstOrNull { (keywords, _) -> keywords.any(value::contains) }?.second
    }

    private fun sameProperty(lhs: AccommodationOption, rhs: AccommodationOption): Boolean {
        val distance = lhs.coordinate.distanceTo(rhs.coordinate)
        val leftName = normalizedName(lhs.name)
        val rightName = normalizedName(rhs.name)
        if (leftName.isEmpty() || rightName.isEmpty()) return false
        val leftBrand = hotelBrand(lhs)
        val rightBrand = hotelBrand(rhs)
        if (leftBrand != null && rightBrand != null && leftBrand != rightBrand) return false
        return (leftName == rightName && distance <= 250) ||
            (namesLikelyMatch(lhs.name, rhs.name) && distance <= 150) ||
            (distance <= 80 && leftBrand != null && leftBrand == rightBrand)
    }

    private fun mergePair(current: AccommodationOption, incoming: AccommodationOption): AccommodationOption = current.copy(
        address = current.address.ifBlank { incoming.address },
        averageAttractionDistanceMeters = positiveMinimum(
            current.averageAttractionDistanceMeters,
            incoming.averageAttractionDistanceMeters
        ),
        hubDistanceMeters = positiveMinimum(current.hubDistanceMeters, incoming.hubDistanceMeters),
        quotes = mergeQuotes(current.quotes, incoming.quotes),
        recommendationReasons = (current.recommendationReasons + incoming.recommendationReasons).distinct(),
        isRecommended = current.isRecommended || incoming.isRecommended,
        brand = current.brand ?: incoming.brand,
        starRating = current.starRating ?: incoming.starRating,
        guestRating = listOfNotNull(current.guestRating, incoming.guestRating).maxOrNull(),
        imageURL = current.imageURL ?: incoming.imageURL,
        officialWebsiteURL = current.officialWebsiteURL ?: incoming.officialWebsiteURL,
        amenities = (current.amenities + incoming.amenities).distinct(),
        tags = (current.tags + incoming.tags).distinct(),
        sources = (current.sources + incoming.sources).distinct()
    )

    private fun mergeQuotes(existing: List<PriceQuote>, incoming: List<PriceQuote>): List<PriceQuote> {
        val byKey = linkedMapOf<String, PriceQuote>()
        (existing + incoming).forEach { quote ->
            val key = quoteKey(quote)
            val current = byKey[key]
            if (current == null || quoteIsNewerOrMoreUseful(quote, current)) byKey[key] = quote
        }
        val concreteProviders = byKey.values.filter { it.amountCNY != null }.mapTo(mutableSetOf()) { it.provider }
        return byKey.values
            .filterNot { quote ->
                quote.amountCNY == null && quote.provider in concreteProviders &&
                    quote.kind in setOf(QuoteKind.CHECK_ON_PROVIDER, QuoteKind.BUDGET_ENVELOPE)
            }
            .sortedWith(
                compareBy<PriceQuote> { it.amountCNY == null }
                    .thenBy { it.amountCNY ?: Int.MAX_VALUE }
                    .thenBy { it.provider }
            )
    }

    private fun quoteKey(quote: PriceQuote): String = listOf(
        quote.provider,
        quote.unit.name,
        quote.amountCNY?.toString().orEmpty(),
        quote.kind.name,
        quote.roomName.orEmpty(),
        quote.bedType.orEmpty(),
        quote.mealPlan.orEmpty(),
        quote.cancellationPolicy.orEmpty()
    ).joinToString("|") { it.trim().lowercase() }

    private fun quoteIsNewerOrMoreUseful(candidate: PriceQuote, current: PriceQuote): Boolean = when {
        current.amountCNY == null && candidate.amountCNY != null -> true
        current.bookingURL.isNullOrBlank() && !candidate.bookingURL.isNullOrBlank() -> true
        else -> (candidate.capturedAt ?: "") > (current.capturedAt ?: "")
    }

    private fun positiveMinimum(lhs: Int, rhs: Int): Int = listOf(lhs, rhs).filter { it > 0 }.minOrNull() ?: 0

    private fun hotelBrand(option: AccommodationOption): String? {
        fun match(value: String): String? {
            val normalized = normalizedName(value)
            return HOTEL_BRANDS.firstOrNull { (_, aliases) -> aliases.any(normalized::contains) }?.first
        }
        // The property name takes precedence over a supplier's corporate group.
        return match(option.name) ?: match(option.brand.orEmpty())
    }

    private val NAME_SEPARATORS = Regex("[\\s·•,，.。()（）\\-—_]+")

    // Specific sub-brands precede parent-name substrings. A shared hotel group
    // (Accor, IHG, etc.) is not property identity evidence.
    private val HOTEL_BRANDS = listOf(
        "grand-mercure" to listOf("美爵", "grandmercure"),
        "ibis-styles" to listOf("宜必思尚品", "ibisstyles"),
        "pullman" to listOf("铂尔曼", "pullman"),
        "novotel" to listOf("诺富特", "novotel"),
        "mercure" to listOf("美居", "mercure"),
        "ibis" to listOf("宜必思", "ibis"),
        "sofitel" to listOf("索菲特", "sofitel"),
        "fairmont" to listOf("费尔蒙", "fairmont"),
        "hampton" to listOf("欢朋", "hampton"),
        "hilton-garden" to listOf("希尔顿花园", "hiltongarden"),
        "doubletree" to listOf("逸林", "doubletree"),
        "conrad" to listOf("康莱德", "conrad"),
        "waldorf" to listOf("华尔道夫", "waldorf"),
        "hilton" to listOf("希尔顿", "hilton"),
        "jw-marriott" to listOf("jw万豪", "jwmarriott"),
        "courtyard" to listOf("万怡", "courtyard"),
        "sheraton" to listOf("喜来登", "sheraton"),
        "westin" to listOf("威斯汀", "westin"),
        "ritz-carlton" to listOf("丽思卡尔顿", "ritzcarlton"),
        "le-meridien" to listOf("艾美", "lemeridien"),
        "marriott" to listOf("万豪", "marriott"),
        "holiday-inn-express" to listOf("智选假日", "holidayinnexpress"),
        "crowne-plaza" to listOf("皇冠假日", "crowneplaza"),
        "holiday-inn" to listOf("假日", "holidayinn"),
        "indigo" to listOf("英迪格", "indigo"),
        "voco" to listOf("voco"),
        "intercontinental" to listOf("洲际", "intercontinental")
    )

    private val OFFICIAL_SITES = listOf(
        listOf("雅高", "铂尔曼", "pullman", "诺富特", "novotel", "美居", "mercure", "宜必思", "ibis", "索菲特", "sofitel", "费尔蒙", "fairmont") to "https://all.accor.com/",
        listOf("希尔顿", "康莱德", "华尔道夫", "欢朋", "hilton", "conrad", "waldorf") to "https://www.hilton.com.cn/zh-CN/",
        listOf("万豪", "喜来登", "威斯汀", "丽思卡尔顿", "艾美", "marriott", "sheraton", "westin", "ritz") to "https://www.marriott.com.cn/",
        listOf("洲际", "皇冠假日", "智选假日", "英迪格", "voco", "ihg", "intercontinental") to "https://www.ihg.com.cn/",
        listOf("全季", "汉庭", "桔子", "星程", "海友", "华住") to "https://www.huazhu.com/",
        listOf("亚朵", "atour") to "https://www.atour.cn/",
        listOf("锦江", "维也纳", "麗枫", "喆啡") to "https://www.jinjianghotels.com/"
    )
}
