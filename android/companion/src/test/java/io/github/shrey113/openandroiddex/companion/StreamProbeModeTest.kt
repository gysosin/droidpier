package io.github.shrey113.openandroiddex.companion

import org.junit.Assert.assertEquals
import org.junit.Test

class StreamProbeModeTest {
    @Test
    fun `missing or unknown mode defaults to latency`() {
        assertEquals(StreamProbeMode.LATENCY, StreamProbeMode.parse(null))
        assertEquals(StreamProbeMode.LATENCY, StreamProbeMode.parse("unknown"))
    }

    @Test
    fun `motion mode is parsed without case sensitivity`() {
        assertEquals(StreamProbeMode.MOTION, StreamProbeMode.parse("motion"))
        assertEquals(StreamProbeMode.MOTION, StreamProbeMode.parse("MOTION"))
    }
}
