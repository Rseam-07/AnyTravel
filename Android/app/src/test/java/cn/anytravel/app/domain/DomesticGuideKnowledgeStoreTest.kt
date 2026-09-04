package cn.anytravel.app.domain

import cn.anytravel.app.model.TripDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DomesticGuideKnowledgeStoreTest {
    @Test
    fun parsesCitySuffixAndKeepsGuideRanking() {
        val store = DomesticGuideKnowledgeStore.fromJson(
            """{"cities":[{"city":"杭州","coord":{"lat":30.25,"lng":120.16},"places":[{"name":"西湖","coord":{"lat":30.24,"lng":120.14},"category":"山水","stayMinutes":180,"tier":"必去"},{"name":"中国茶叶博物馆","coord":{"lat":30.22,"lng":120.11},"category":"博物馆","stayMinutes":120,"tier":"推荐"}]}]}"""
        )

        val pack = store.destination(TripDraft(destination = "杭州市"))

        assertNotNull(pack)
        assertEquals("杭州", pack?.canonicalName)
        assertEquals(listOf("西湖", "中国茶叶博物馆"), pack?.places?.map { it.name })
        assertEquals(1, pack?.places?.first()?.popularityRank)
        assertTrue(pack?.sourceNote?.contains("公开热度") == true)
    }
}
