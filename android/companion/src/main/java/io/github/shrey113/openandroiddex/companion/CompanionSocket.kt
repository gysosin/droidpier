package io.github.shrey113.openandroiddex.companion

import android.os.Build
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.min

internal class CompanionSocket(
    private val sessionToken: String,
    private val onConnected: () -> Unit,
    private val onUserDisconnected: () -> Unit,
) : WebSocketListener() {
    private val client = OkHttpClient.Builder()
        .pingInterval(10, TimeUnit.SECONDS)
        .build()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var socket: WebSocket? = null
    @Volatile private var connected = false
    private var disconnectTask: ScheduledFuture<*>? = null
    private var reconnectTask: ScheduledFuture<*>? = null
    private var attempts = 0
    @Volatile private var stopped = false
    @Volatile private var disconnectRequestId: String? = null

    @Synchronized
    fun connect() {
        if (stopped) return
        reconnectTask?.cancel(false)
        val request = Request.Builder()
            .url("ws://127.0.0.1:3699/companion")
            .header("X-Open-Dex-Token", sessionToken)
            .build()
        socket = client.newWebSocket(request, this)
    }

    fun send(type: String, data: JSONObject = JSONObject()) {
        socket?.send(ProtocolEnvelope.create(type, data).toString())
    }

    @Synchronized
    override fun onOpen(webSocket: WebSocket, response: Response) {
        if (stopped || webSocket !== socket) { webSocket.cancel(); return }
        connected = true
        Log.i(TAG, "Authenticated desktop socket opened")
        attempts = 0
        CompanionEventBus.attach(this)
        CompanionConnection.update(CompanionConnection.State.CONNECTED)
        send(
            "companion.hello",
            JSONObject()
                .put("sdk", Build.VERSION.SDK_INT)
                .put(
                    "capabilities",
                    JSONArray()
                        .put("battery")
                        .put("device-state")
                        .put("notifications")
                        .put("notification-actions")
                        .put("permissions")
                        .put("volume-state"),
                ).put("sessionDisconnect", true),
        )
        onConnected()
        // Replay the notifications already on the phone. The listener publishes
        // them once, on onListenerConnected, which normally fires before this
        // desktop socket exists — so without this the desktop only ever saw
        // notifications posted after it connected, never the ones already there.
        NotificationCommandBridge.publishActive()
    }

    @Synchronized
    override fun onMessage(webSocket: WebSocket, text: String) {
        if (stopped || webSocket !== socket) return
        val message = runCatching { JSONObject(text) }.getOrNull() ?: return
        if (message.optInt("v") != ProtocolEnvelope.VERSION) return
        when (message.optString("type")) {
            "companion.welcome" -> {
                if (message.optJSONObject("data")?.optBoolean("sessionDisconnect") == true) {
                    CompanionConnection.update(CompanionConnection.State.CONNECTED, ::requestDisconnect)
                }
            }
            "companion.disconnect.ack" -> {
                if (disconnectRequestId != null && message.optJSONObject("data")?.optString("replyTo") == disconnectRequestId) {
                    close()
                    onUserDisconnected()
                }
            }
            "ping" -> send("pong", JSONObject().put("replyTo", message.optString("id")))
            "telemetry.request" -> {
                onConnected()
                // A re-sync request replays active notifications too, so a
                // reconnect never leaves the desktop's list stale.
                NotificationCommandBridge.publishActive()
            }
            "notification.dismiss" -> replyNotificationCommand(message) {
                val key = message.optJSONObject("data")?.optString("key").orEmpty()
                if (key.isEmpty()) NotificationCommandResult(false, "not-found")
                else NotificationCommandBridge.dismiss(key)
            }
            "notification.activate" -> replyNotificationCommand(message) {
                val data = message.optJSONObject("data")
                val key = data?.optString("key").orEmpty()
                val displayId = data?.takeIf { it.has("displayId") }?.optInt("displayId")
                if (key.isEmpty()) NotificationCommandResult(false, "not-found")
                else NotificationCommandBridge.activate(key, displayId)
            }
            "notification.dismissAll" -> replyNotificationCommand(message) {
                NotificationCommandBridge.dismissAll()
            }
        }
    }

    private fun replyNotificationCommand(
        message: JSONObject,
        command: () -> NotificationCommandResult,
    ) {
        val result = command()
        send(
            "notification.command.result",
            JSONObject()
                .put("replyTo", message.optString("id"))
                .put("success", result.success)
                .apply { result.error?.let { put("error", it) } },
        )
    }

    @Synchronized
    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        if (stopped || webSocket !== socket) return
        Log.w(TAG, "Desktop socket failure: ${t.javaClass.simpleName}")
        CompanionEventBus.detach(this)
        scheduleReconnect()
    }

    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        webSocket.close(code, null)
    }

    @Synchronized
    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        if (stopped || webSocket !== socket) return
        Log.i(TAG, "Desktop socket closed: $code")
        CompanionEventBus.detach(this)
        scheduleReconnect()
    }

    @Synchronized
    private fun scheduleReconnect() {
        if (stopped) return
        connected = false
        disconnectTask?.cancel(false)
        disconnectRequestId = null
        CompanionConnection.update(CompanionConnection.State.RECONNECTING)
        val delaySeconds = min(30, 1 shl min(attempts++, 5))
        reconnectTask?.cancel(false)
        reconnectTask = scheduler.schedule(::connect, delaySeconds.toLong(), TimeUnit.SECONDS)
    }

    @Synchronized
    fun close() {
        stopped = true
        connected = false
        disconnectTask?.cancel(true)
        disconnectRequestId = null
        reconnectTask?.cancel(true)
        CompanionEventBus.detach(this)
        socket?.close(1000, "service stopped")
        client.dispatcher.executorService.shutdown()
        scheduler.shutdownNow()
        CompanionConnection.update(CompanionConnection.State.DISCONNECTED)
    }

    @Synchronized
    private fun requestDisconnect() {
        if (stopped || !connected || disconnectRequestId != null) return
        val envelope = ProtocolEnvelope.create("companion.disconnect.request")
        disconnectRequestId = envelope.getString("id")
        if (socket?.send(envelope.toString()) != true) {
            disconnectRequestId = null
            return
        }
        CompanionConnection.update(CompanionConnection.State.DISCONNECTING)
        disconnectTask = scheduler.schedule({
            synchronized(this) {
                if (!stopped && connected && disconnectRequestId != null) {
                    disconnectRequestId = null
                    CompanionConnection.update(CompanionConnection.State.CONNECTED, ::requestDisconnect)
                }
            }
        }, 10, TimeUnit.SECONDS)
    }

    companion object {
        private const val TAG = "OpenDexCompanion"
    }
}
