package cn.anytravel.app.data

import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLStreamHandler
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkClientTest {
    @Test
    fun boundedReaderPreservesUtf8() {
        val text = "地图会记得每一次抵达"

        val result = ByteArrayInputStream(text.toByteArray()).readUtf8WithLimit(128)

        assertEquals(text, result)
    }

    @Test
    fun boundedReaderRejectsOversizedPayloadBeforeItCanFillMemory() {
        val payload = ByteArray(1_025) { 1 }

        assertThrows(ResponseTooLargeException::class.java) {
            ByteArrayInputStream(payload).readUtf8WithLimit(1_024)
        }
    }

    @Test
    fun configurationFailureStillDisconnects() {
        val connection = TestConnection(ByteArray(0))

        assertThrows(IllegalStateException::class.java) {
            runBlocking {
                NetworkClient.request(connection.requestURL, configure = { error("Invalid client configuration") })
            }
        }

        assertTrue(connection.disconnected)
    }

    @Test
    fun oversizedResponseClosesItsStreamAndConnection() {
        val connection = TestConnection(ByteArray(1_025))

        assertThrows(ResponseTooLargeException::class.java) {
            runBlocking { NetworkClient.request(connection.requestURL, maxResponseBytes = 1_024) }
        }

        assertTrue(connection.streamClosed)
        assertTrue(connection.disconnected)
    }

    private class TestConnection(payload: ByteArray) : HttpURLConnection(URL("https://example.invalid")) {
        var disconnected = false
        var streamClosed = false
        private val responseStream = object : ByteArrayInputStream(payload) {
            override fun close() {
                streamClosed = true
                super.close()
            }
        }
        val requestURL = URL(null, "https://example.invalid", object : URLStreamHandler() {
            override fun openConnection(url: URL) = this@TestConnection
        })

        override fun connect() = Unit
        override fun disconnect() { disconnected = true }
        override fun usingProxy() = false
        override fun getResponseCode() = 200
        override fun getInputStream() = responseStream
    }
}
