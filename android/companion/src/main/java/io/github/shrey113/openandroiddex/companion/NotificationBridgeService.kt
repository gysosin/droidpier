package io.github.shrey113.openandroiddex.companion

import android.app.ActivityOptions
import android.app.PendingIntent
import android.os.Build
import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

class NotificationBridgeService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        NotificationCommandBridge.attach(this)
        publishActive()
    }

    override fun onListenerDisconnected() {
        NotificationCommandBridge.detach(this)
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        NotificationCommandBridge.detach(this)
        super.onDestroy()
    }

    override fun onNotificationPosted(notification: StatusBarNotification) {
        publish(notification)
    }

    private fun publish(notification: StatusBarNotification) {
        val extras = notification.notification.extras
        CompanionEventBus.send(
            "notification.posted",
            JSONObject()
                .put("key", notification.key)
                .put("packageName", notification.packageName)
                .put("timestamp", notification.postTime)
                .put("title", extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty())
                .put("body", extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()),
        )
    }

    internal fun publishActive() {
        activeNotifications.orEmpty().forEach(::publish)
    }

    override fun onNotificationRemoved(notification: StatusBarNotification) {
        CompanionEventBus.send(
            "notification.removed",
            JSONObject().put("key", notification.key),
        )
    }

    internal fun dismiss(key: String): NotificationCommandResult {
        if (activeNotifications.orEmpty().none { it.key == key }) {
            return NotificationCommandResult(false, "not-found")
        }
        cancelNotification(key)
        return NotificationCommandResult(true)
    }

    internal fun dismissAll(): NotificationCommandResult {
        cancelAllNotifications()
        return NotificationCommandResult(true)
    }

    internal fun activate(key: String, displayId: Int?): NotificationCommandResult {
        val notification = activeNotifications.orEmpty().firstOrNull { it.key == key }
            ?: return NotificationCommandResult(false, "not-found")
        val contentIntent = notification.notification.contentIntent
            ?: return NotificationCommandResult(false, "unavailable")
        return try {
            val options = if (displayId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ActivityOptions.makeBasic().setLaunchDisplayId(displayId).toBundle()
            } else {
                null
            }
            contentIntent.send(this, 0, null, null, null, null, options)
            NotificationCommandResult(true)
        } catch (_: PendingIntent.CanceledException) {
            NotificationCommandResult(false, "not-found")
        } catch (_: SecurityException) {
            NotificationCommandResult(false, "unavailable")
        }
    }
}

internal data class NotificationCommandResult(
    val success: Boolean,
    val error: String? = null,
)

internal object NotificationCommandBridge {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val observers = mutableSetOf<() -> Unit>()
    val isConnected: Boolean get() = listener != null
    fun observe(observer: () -> Unit) { observers.add(observer); observer() }
    fun remove(observer: () -> Unit) { observers.remove(observer) }
    private fun changed() { handler.post { observers.toList().forEach { it() } } }

    @Volatile
    private var listener: NotificationBridgeService? = null

    fun attach(value: NotificationBridgeService) {
        listener = value
        changed()
    }

    fun detach(value: NotificationBridgeService) {
        if (listener === value) { listener = null; changed() }
    }

    fun dismiss(key: String): NotificationCommandResult = listener?.dismiss(key)
        ?: NotificationCommandResult(false, "unavailable")

    fun dismissAll(): NotificationCommandResult = listener?.dismissAll()
        ?: NotificationCommandResult(false, "unavailable")

    fun publishActive() {
        listener?.publishActive()
    }

    fun activate(key: String, displayId: Int?): NotificationCommandResult =
        listener?.activate(key, displayId)
            ?: NotificationCommandResult(false, "unavailable")
}
