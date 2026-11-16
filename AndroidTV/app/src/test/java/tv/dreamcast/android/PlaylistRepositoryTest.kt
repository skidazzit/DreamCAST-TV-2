package tv.dreamcast.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaylistRepositoryTest {
    @Test
    fun parsesGroupsAndEpgAttributes() {
        val sample = """
            #EXTM3U
            #EXTINF:-1 tvg-id="espn.us" tvg-logo="https://example.com/espn.png" group-title="Sports",ESPN
            https://example.com/live/espn.m3u8
            #EXTINF:-1 group-title="News",Global News
            https://example.com/live/news.m3u8
        """.trimIndent()
        val channels = PlaylistRepository.parse(sample)
        assertEquals(2, channels.size)
        assertEquals("ESPN", channels.first().name)
        assertEquals("Sports", channels.first().group)
        assertEquals("espn.us", channels.first().epgId)
        assertEquals("News", channels.last().group)
    }

    @Test
    fun ignoresUnusableEntriesAndDuplicateStreamUrls() {
        val sample = """
            #EXTM3U
            #EXTINF:-1,One
            https://example.com/one.m3u8
            #EXTINF:-1,Duplicate
            https://example.com/one.m3u8
            #EXTINF:-1,Invalid
            ftp://example.com/invalid
        """.trimIndent()
        val channels = PlaylistRepository.parse(sample)
        assertEquals(1, channels.size)
        assertTrue(channels.first().name == "One")
    }
}
