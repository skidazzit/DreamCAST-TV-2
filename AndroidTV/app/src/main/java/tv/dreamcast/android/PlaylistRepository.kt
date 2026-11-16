package tv.dreamcast.android

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

data class TvChannel(
    val id: String,
    val name: String,
    val streamUrl: String,
    val group: String,
    val logoUrl: String = "",
    val epgId: String = ""
)

/** Imports user-provided playlists only. No bundled channels or credentials. */
class PlaylistRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences("dreamcast_playlist", Context.MODE_PRIVATE)

    fun savedUrl(): String = prefs.getString("playlist_url", "") ?: ""
    fun lastChannelId(): String = prefs.getString("last_channel_id", "") ?: ""
    fun rememberChannel(id: String) { prefs.edit().putString("last_channel_id", id).apply() }

    suspend fun importUrl(url: String): List<TvChannel> = withContext(Dispatchers.IO) {
        require(url.startsWith("https://", true) || url.startsWith("http://", true)) {
            "Enter an HTTP or HTTPS M3U address."
        }
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 12_000
            connection.readTimeout = 25_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("Accept", "audio/x-mpegurl, application/x-mpegURL, text/plain, */*")
            if (connection.responseCode !in 200..299) error("Playlist server returned HTTP ${connection.responseCode}")
            val lines = connection.inputStream.bufferedReader().use { reader ->
                // Limit remote input to avoid exhausting TV memory.
                val text = reader.readText()
                require(text.length <= 30_000_000) { "Playlist exceeds 30 MB." }
                text
            }
            val channels = parse(lines)
            require(channels.isNotEmpty()) { "No playable channels were found." }
            prefs.edit().putString("playlist_url", url).apply()
            channels
        } finally {
            connection.disconnect()
        }
    }

    suspend fun importFile(uri: Uri): List<TvChannel> = withContext(Dispatchers.IO) {
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            ?: error("Could not open playlist file.")
        require(text.length <= 30_000_000) { "Playlist exceeds 30 MB." }
        val channels = parse(text)
        require(channels.isNotEmpty()) { "No playable channels were found." }
        // File URI access may be temporary; keep the playlist content in app-local storage.
        context.openFileOutput("playlist.m3u", Context.MODE_PRIVATE).bufferedWriter().use { it.write(text) }
        prefs.edit().remove("playlist_url").apply()
        channels
    }

    suspend fun restore(): List<TvChannel> = withContext(Dispatchers.IO) {
        val remote = savedUrl()
        if (remote.isNotBlank()) {
            importUrl(remote)
        } else {
            runCatching {
                context.openFileInput("playlist.m3u").bufferedReader().use { parse(it.readText()) }
            }.getOrDefault(emptyList())
        }
    }

    companion object {
        private val attribute = Regex("""([\w-]+)\s*=\s*"([^"]*)"""")

        fun parse(content: String): List<TvChannel> {
            val channels = mutableListOf<TvChannel>()
            var details: Map<String, String> = emptyMap()
            var displayName = ""
            var group = "Other"
            var pending = false
            content.lineSequence().forEach { raw ->
                val line = raw.trim()
                when {
                    line.startsWith("#EXTINF", ignoreCase = true) -> {
                        val metadata = line.substringBeforeLast(',', "")
                        details = attribute.findAll(metadata).associate {
                            it.groupValues[1].lowercase() to it.groupValues[2]
                        }
                        displayName = line.substringAfterLast(',', "").trim()
                            .ifEmpty { details["tvg-name"].orEmpty() }
                        group = details["group-title"]?.ifBlank { "Other" } ?: "Other"
                        pending = true
                    }
                    line.startsWith("#EXTGRP:", ignoreCase = true) && pending ->
                        group = line.substringAfter(':').ifBlank { "Other" }.trim()
                    line.isNotBlank() && !line.startsWith("#") && pending -> {
                        if (line.startsWith("http://", true) || line.startsWith("https://", true)) {
                            val name = displayName.ifBlank { "Channel ${channels.size + 1}" }
                            channels += TvChannel(
                                id = "${details["tvg-id"].orEmpty()}|${line}",
                                name = name,
                                streamUrl = line,
                                group = group,
                                logoUrl = details["tvg-logo"].orEmpty(),
                                epgId = details["tvg-id"].orEmpty()
                            )
                        }
                        pending = false
                    }
                }
            }
            return channels.distinctBy { it.streamUrl }
        }
    }
}
