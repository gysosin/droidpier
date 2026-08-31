package io.github.shrey113.openandroiddex.companion

import org.json.JSONObject
import java.time.Instant
import java.util.UUID

internal object ProtocolEnvelope {
    const val VERSION = 1

    fun create(type: String, data: JSONObject = JSONObject()): JSONObject = JSONObject()
        .put("v", VERSION)
        .put("id", UUID.randomUUID().toString())
        .put("type", type)
        .put("timestamp", Instant.now().toString())
        .put("data", data)
}
