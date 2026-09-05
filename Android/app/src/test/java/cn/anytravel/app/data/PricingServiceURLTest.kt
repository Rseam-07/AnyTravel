package cn.anytravel.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PricingServiceURLTest {
    @Test
    fun publicServiceRequiresHttpsAndKeepsPath() {
        assertEquals("https://travel.example/api/", normalizePricingServiceURL("https://travel.example/api").toString())
        assertThrows(PricingException::class.java) { normalizePricingServiceURL("http://travel.example") }
        assertThrows(PricingException::class.java) { normalizePricingServiceURL("ftp://travel.example") }
    }

    @Test
    fun localDevelopmentMayUseHttp() {
        assertEquals("http://localhost:8787/", normalizePricingServiceURL("http://localhost:8787").toString())
        assertEquals("http://127.0.0.1:8787/", normalizePricingServiceURL("http://127.0.0.1:8787").toString())
    }

    @Test
    fun credentialsQueriesAndFragmentsAreRejected() {
        assertThrows(PricingException::class.java) { normalizePricingServiceURL("https://user:secret@travel.example") }
        assertThrows(PricingException::class.java) { normalizePricingServiceURL("https://travel.example?key=value") }
        assertThrows(PricingException::class.java) { normalizePricingServiceURL("https://travel.example/#fragment") }
    }
}
