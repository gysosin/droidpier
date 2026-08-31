package io.github.shrey113.openandroiddex.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Base64
import java.io.ByteArrayOutputStream
import org.json.JSONObject

class CompanionService : Service() {
    private var socket: CompanionSocket? = null
    private var receiverRegistered = false

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            sendBattery(intent)
        }
    }

    private var mediaManager: MediaSessionManager? = null
    private val mediaControllers = mutableListOf<MediaController>()

    private val mediaCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = sendMedia()
        override fun onMetadataChanged(metadata: MediaMetadata?) = sendMedia()
        override fun onSessionDestroyed() = sendMedia()
    }

    private val sessionsChangedListener =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            attachMediaControllers(controllers ?: emptyList())
            sendMedia()
        }

    private fun setupMedia() {
        val manager = getSystemService(MediaSessionManager::class.java) ?: return
        mediaManager = manager
        val component = ComponentName(this, NotificationBridgeService::class.java)
        try {
            manager.addOnActiveSessionsChangedListener(
                sessionsChangedListener,
                component,
            )
            attachMediaControllers(manager.getActiveSessions(component))
            sendMedia()
        } catch (_: SecurityException) {
            // Notification access not granted yet; media stays unavailable.
        }
    }

    private fun attachMediaControllers(controllers: List<MediaController>) {
        mediaControllers.forEach { it.unregisterCallback(mediaCallback) }
        mediaControllers.clear()
        controllers.forEach {
            it.registerCallback(mediaCallback)
            mediaControllers.add(it)
        }
    }

    private fun teardownMedia() {
        mediaControllers.forEach { it.unregisterCallback(mediaCallback) }
        mediaControllers.clear()
        mediaManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        mediaManager = null
    }

    private fun sendMedia() {
        val active = mediaControllers.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: mediaControllers.firstOrNull()
        if (active == null) {
            CompanionEventBus.send(
                "media.update",
                JSONObject().put("playback", "unavailable"),
            )
            return
        }
        val meta = active.metadata
        val state = active.playbackState
        val playback = when (state?.state) {
            PlaybackState.STATE_PLAYING -> "playing"
            PlaybackState.STATE_PAUSED -> "paused"
            else -> "stopped"
        }
        val json = JSONObject()
            .put("playback", playback)
            .put(
                "title",
                meta?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty(),
            )
            .put(
                "artist",
                (meta?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: meta?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST))
                    .orEmpty(),
            )
            .put("positionMs", state?.position ?: 0L)
            .put(
                "durationMs",
                meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L,
            )
        val art = meta?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: meta?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: meta?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        if (art != null) {
            try {
                val scaled = Bitmap.createScaledBitmap(art, 160, 160, true)
                val out = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
                json.put(
                    "artwork",
                    Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP),
                )
            } catch (_: Exception) {
                // A bad bitmap must not stop the rest of the media update.
            }
        }
        CompanionEventBus.send("media.update", json)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, foregroundNotification())
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val token = intent?.getStringExtra(EXTRA_SESSION_TOKEN)
        if (token == null || !TOKEN_PATTERN.matches(token)) {
            stopSelf()
            return START_NOT_STICKY
        }
        socket?.close()
        CompanionConnection.update(CompanionConnection.State.CONNECTING)
        socket = CompanionSocket(token, ::sendSnapshot) {
            android.os.Handler(mainLooper).post { stopSelf() }
        }.also { it.connect() }
        setupMedia()
        return START_STICKY
    }

    override fun onDestroy() {
        socket?.close()
        socket = null
        teardownMedia()
        if (receiverRegistered) unregisterReceiver(batteryReceiver)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun sendSnapshot() {
        sendBattery(registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)))
        sendDeviceState()
        sendMedia()
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ).orEmpty()
        CompanionEventBus.send(
            "permissions.update",
            JSONObject().put(
                "notifications",
                enabledListeners.contains(packageName),
            ),
        )
        NotificationCommandBridge.publishActive()
    }

    private fun sendDeviceState() {
        val audio = getSystemService(AudioManager::class.java)
        val volumes = JSONObject()
        listOf(
            "voiceCall" to AudioManager.STREAM_VOICE_CALL,
            "system" to AudioManager.STREAM_SYSTEM,
            "ring" to AudioManager.STREAM_RING,
            "music" to AudioManager.STREAM_MUSIC,
            "alarm" to AudioManager.STREAM_ALARM,
            "notification" to AudioManager.STREAM_NOTIFICATION,
        ).forEach { (name, stream) ->
            volumes.put(
                name,
                JSONObject()
                    .put("current", audio.getStreamVolume(stream))
                    .put("maximum", audio.getStreamMaxVolume(stream)),
            )
        }
        CompanionEventBus.send(
            "device.update",
            JSONObject()
                .put(
                    "wifiEnabled",
                    getSystemService(WifiManager::class.java).isWifiEnabled,
                )
                .put(
                    "bluetoothEnabled",
                    Settings.Global.getInt(contentResolver, "bluetooth_on", 0) == 1,
                )
                .put(
                    "rotationLocked",
                    Settings.System.getInt(
                        contentResolver,
                        Settings.System.ACCELEROMETER_ROTATION,
                        1,
                    ) == 0,
                )
                .put(
                    "airplaneMode",
                    Settings.Global.getInt(
                        contentResolver,
                        Settings.Global.AIRPLANE_MODE_ON,
                        0,
                    ) == 1,
                )
                .put(
                    "mobileDataEnabled",
                    Settings.Global.getInt(contentResolver, "mobile_data", 0) == 1,
                )
                .put(
                    "locationEnabled",
                    Settings.Secure.getInt(
                        contentResolver,
                        Settings.Secure.LOCATION_MODE,
                        0,
                    ) != 0,
                )
                .put("volume", volumes),
        )
    }

    private fun sendBattery(intent: Intent?) {
        if (intent == null) return
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val percentage = if (level >= 0 && scale > 0) level * 100 / scale else -1
        CompanionEventBus.send(
            "battery.update",
            JSONObject()
                .put("percentage", percentage)
                .put(
                    "charging",
                    status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL,
                ),
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Desktop connection",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun foregroundNotification(): Notification = Notification.Builder(this, CHANNEL_ID)
        .setContentTitle("DroidPier Companion")
        .setContentText("Desktop connection service · open the app for status")
        .setSmallIcon(android.R.drawable.stat_notify_sync)
        .setOngoing(true)
        .build()

    companion object {
        const val EXTRA_SESSION_TOKEN = "session_token"
        private const val CHANNEL_ID = "open_dex_connection"
        private const val NOTIFICATION_ID = 3699
        private val TOKEN_PATTERN = Regex("^[A-Za-z0-9_-]{32,128}$")
    }
}
