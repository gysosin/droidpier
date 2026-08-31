package io.github.shrey113.openandroiddex.companion

import org.json.JSONObject

internal object CompanionEventBus {
    @Volatile
    private var socket: CompanionSocket? = null

    fun attach(value: CompanionSocket) {
        socket = value
    }

    fun detach(value: CompanionSocket) {
        if (socket === value) socket = null
    }

    fun send(type: String, data: JSONObject = JSONObject()) {
        socket?.send(type, data)
    }
}
