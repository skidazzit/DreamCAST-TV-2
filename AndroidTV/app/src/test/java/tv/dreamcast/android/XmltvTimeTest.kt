package tv.dreamcast.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class XmltvTimeTest {
    @Test
    fun parsesUtcAndOffsets() {
        val utc = EpgRepository.timeMillis("20261119120000 +0000")
        val east = EpgRepository.timeMillis("20261119070000 -0500")
        assertEquals(utc, east)
    }

    @Test
    fun rejectsBadTime() {
        assertNull(EpgRepository.timeMillis("not-a-time"))
    }
}
