package tv.dreamcast.android

import android.content.Context
import android.util.Xml
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.xmlpull.v1.XmlPullParser
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.zip.GZIPInputStream

data class EpgProgramme(
    val channelId: String,
    val title: String,
    val startMillis: Long,
    val endMillis: Long,
    val description: String = ""
)

class EpgRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences("dreamcast_epg", Context.MODE_PRIVATE)
    fun savedUrl(): String = prefs.getString("xmltv_url", "").orEmpty()
    fun saveUrl(url: String) = prefs.edit().putString("xmltv_url", url).apply()

    suspend fun load(url: String): List<EpgProgramme> = withContext(Dispatchers.IO) {
        require(url.startsWith("https://", true) || url.startsWith("http://", true)) {
            "Enter an HTTP or HTTPS XMLTV address."
        }
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 12_000
            connection.readTimeout = 30_000
            if (connection.responseCode !in 200..299) error("EPG server returned HTTP ${connection.responseCode}")
            val programmes = connection.inputStream.buffered().use { source ->
                val decoded: InputStream = if (url.endsWith(".gz", true) ||
                    connection.contentType?.contains("gzip", true) == true) GZIPInputStream(source) else source
                decoded.use { parse(it) }
            }
            saveUrl(url)
            programmes
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private val xmltvDate = DateTimeFormatter.ofPattern("yyyyMMddHHmmss", Locale.US)
        private val compactDate = DateTimeFormatter.ofPattern("yyyyMMddHHmm", Locale.US)
        private val offsetPattern = Regex("""^\s*(\d{12}|\d{14})(?:\s*([+-]\d{4}))?.*""")

        fun timeMillis(raw: String): Long? {
            val match = offsetPattern.matchEntire(raw) ?: return null
            return runCatching {
                val timestamp = match.groupValues[1]
                val local = if (timestamp.length == 14) LocalDateTime.parse(timestamp, xmltvDate)
                    else LocalDateTime.parse(timestamp, compactDate)
                val tz = match.groupValues[2]
                val offset = if (tz.isNotEmpty()) ZoneOffset.of(tz.substring(0, 3) + ":" + tz.substring(3))
                    else ZoneOffset.UTC
                local.toInstant(offset).toEpochMilli()
            }.getOrNull()
        }

        fun parse(stream: InputStream): List<EpgProgramme> {
            val parser = Xml.newPullParser().apply {
                setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
                setInput(stream, null)
            }
            val result = ArrayList<EpgProgramme>()
            var channel = ""
            var start = 0L
            var end = 0L
            var title = ""
            var description = ""
            var currentText: String? = null

            while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> when (parser.name) {
                        "programme" -> {
                            channel = parser.getAttributeValue(null, "channel").orEmpty()
                            start = timeMillis(parser.getAttributeValue(null, "start").orEmpty()) ?: 0
                            end = timeMillis(parser.getAttributeValue(null, "stop").orEmpty()) ?: 0
                            title = ""
                            description = ""
                        }
                        "title", "desc" -> currentText = parser.name
                    }
                    XmlPullParser.TEXT -> when (currentText) {
                        "title" -> title += parser.text
                        "desc" -> description += parser.text
                    }
                    XmlPullParser.END_TAG -> when (parser.name) {
                        "title", "desc" -> currentText = null
                        "programme" -> {
                            if (channel.isNotBlank() && title.isNotBlank() && end > start) {
                                result.add(EpgProgramme(channel, title, start, end, description))
                            }
                            currentText = null
                        }
                    }
                }
                parser.next()
            }
            return result.sortedWith(compareBy<EpgProgramme> { it.channelId }.thenBy { it.startMillis })
        }

        fun forChannel(programmes: List<EpgProgramme>, channel: TvChannel): List<EpgProgramme> {
            val id = channel.epgId.trim()
            if (id.isEmpty()) return emptyList()
            return programmes.filter { it.channelId.equals(id, ignoreCase = true) }
        }
    }
}
