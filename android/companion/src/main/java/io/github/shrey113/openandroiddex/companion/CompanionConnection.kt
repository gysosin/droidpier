package io.github.shrey113.openandroiddex.companion

import android.os.Handler
import android.os.Looper

/** Process-local UI state. Session credentials are never persisted. */
internal object CompanionConnection {
    enum class State { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, DISCONNECTING }
    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableSetOf<() -> Unit>()
    @Volatile var state = State.DISCONNECTED
        private set
    @Volatile var canDisconnect = false
        private set
    @Volatile private var request: (() -> Unit)? = null

    fun update(value: State, disconnect: (() -> Unit)? = null) {
        state = value
        request = disconnect
        canDisconnect = disconnect != null
        handler.post { observers.toList().forEach { it() } }
    }

    fun observe(observer: () -> Unit) { observers.add(observer); observer() }
    fun remove(observer: () -> Unit) { observers.remove(observer) }
    fun disconnect() { request?.invoke() }
}
