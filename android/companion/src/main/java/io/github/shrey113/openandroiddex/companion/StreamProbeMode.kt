package io.github.shrey113.openandroiddex.companion

internal enum class StreamProbeMode {
    LATENCY,
    MOTION;

    companion object {
        fun parse(value: String?): StreamProbeMode =
            if (value.equals("motion", ignoreCase = true)) MOTION else LATENCY
    }
}
