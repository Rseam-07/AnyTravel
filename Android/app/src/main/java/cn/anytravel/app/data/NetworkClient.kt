package cn.anytravel.app.data

import cn.anytravel.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Small shared HTTP boundary for the Android clients.
 *
 * It keeps timeout, cancellation, response-size and connection cleanup rules in
 * one place. Callers still own protocol-specific status messages and parsing.
 */
internal object NetworkClient {
    private const val DEFAULT_MAX_RESPONSE_BYTES = 12 * 1024 * 1024

    val userAgent: String
        get() = "AnyTravel-Android/${BuildConfig.VERSION_NAME} (+https://github.com/Rseam-07/AnyTravel)"

    suspend fun request(
        url: URL,
        method: String = "GET",
        body: ByteArray? = null,
        headers: Map<String, String> = emptyMap(),
        connectTimeoutMillis: Int = 10_000,
        readTimeoutMillis: Int = 30_000,
        maxResponseBytes: Int = DEFAULT_MAX_RESPONSE_BYTES,
        configure: (HttpURLConnection) -> Unit = {}
    ): NetworkResponse = runInterruptible(Dispatchers.IO) {
        require(connectTimeoutMillis > 0) { "connectTimeoutMillis must be positive" }
        require(readTimeoutMillis > 0) { "readTimeoutMillis must be positive" }
        require(maxResponseBytes > 0) { "maxResponseBytes must be positive" }

        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.apply {
                requestMethod = method
                instanceFollowRedirects = true
                connectTimeout = connectTimeoutMillis
                readTimeout = readTimeoutMillis
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", userAgent)
                headers.forEach { (key, value) -> setRequestProperty(key, value) }
                configure(this)
            }
            if (body != null) {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val responseBody = stream?.use { it.readUtf8WithLimit(maxResponseBytes) }.orEmpty()
            val responseHeaders = connection.headerFields.entries.mapNotNull { (key, values) ->
                key?.let { it to values.orEmpty() }
            }.toMap()
            NetworkResponse(status, responseBody, responseHeaders)
        } finally {
            connection.disconnect()
        }
    }
}

internal data class NetworkResponse(
    val status: Int,
    val body: String,
    val headers: Map<String, List<String>>
)

internal class ResponseTooLargeException(limitBytes: Int) : Exception(
    "网络响应超过 ${(limitBytes / 1024.0 / 1024.0).let { "%.1f".format(it) }} MB 安全上限"
)

internal fun InputStream.readUtf8WithLimit(limitBytes: Int): String {
    require(limitBytes > 0) { "limitBytes must be positive" }
    val output = ByteArrayOutputStream(minOf(limitBytes, 64 * 1024))
    val buffer = ByteArray(16 * 1024)
    var total = 0
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        total += count
        if (total > limitBytes) throw ResponseTooLargeException(limitBytes)
        output.write(buffer, 0, count)
    }
    return output.toString(Charsets.UTF_8.name())
}
