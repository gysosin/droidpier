package io.github.shrey113.openandroiddex.companion

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Local setup and explicit controls; connecting is initiated by the desktop. */
class SetupActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var permissions: TextView
    private lateinit var disconnect: Button
    private val observer: () -> Unit = { refresh() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(32), dp(24), dp(32))
        }
        fun text(value: String, size: Float = 16f, bold: Boolean = false): TextView {
            return TextView(this).apply {
                text = value
                textSize = size
                if (bold) setTypeface(typeface, Typeface.BOLD)
                setPadding(0, dp(8), 0, dp(12))
                column.addView(this, LinearLayout.LayoutParams(-1, -2))
            }
        }
        fun button(label: String, action: () -> Unit): Button {
            return Button(this).apply {
                text = label
                isAllCaps = false
                minHeight = dp(48)
                setOnClickListener { action() }
                column.addView(this, LinearLayout.LayoutParams(-1, -2).apply {
                    bottomMargin = dp(8)
                })
            }
        }
        text("DroidPier", 32f, true)
        text("Your Android. A bigger workspace.", 18f)
        status = text("Not connected", 22f, true).apply {
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        text("Connect from your computer", 20f, true)
        text("1. Download DroidPier on your computer.\n\n2. Enable Developer options and USB debugging on this phone. Connect a USB data cable and approve the computer's authorization prompt.\n\n3. Select this phone in DroidPier. For wireless use on Android 11 or later, open Wireless debugging and choose pairing by QR code or pairing code. Scan the QR code shown by DroidPier on the computer, or enter the phone’s pairing details manually.")
        button("Open developer settings") { openSettings(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS) }
        text("Permissions", 20f, true)
        permissions = text("")
        text("Connection notification", 18f, true)
        text("Shows DroidPier’s own connection status on this phone. This does not grant access to notifications from other apps.")
        button("Allow connection notifications") {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
            } else {
                openSettings(Settings.ACTION_APP_NOTIFICATION_SETTINGS, true)
            }
        }
        text("Phone notification access", 18f, true)
        button("Open notification access") { openNotificationAccess() }
        if (Build.VERSION.SDK_INT >= 33) {
            text("If Android says ‘Restricted setting’, first review whether you trust this APK. In DroidPier’s App info, open the top-right menu and choose ‘Allow restricted settings’ if your device offers it. Then return here to grant notification access. Work or managed phones may prohibit this access.")
        }
        button("Open app info") { openAppInfo() }
        text("Keep Play Protect enabled. If Google has not seen this app before, let it scan the APK. Release signing protects updates; it does not mean Google has approved the app. Download only from the project’s GitHub releases.")
        text("Notification access is optional. It lets DroidPier show and control phone notifications on your connected computer. Only approve computers you trust.")
        disconnect = button("Disconnect desktop") { CompanionConnection.disconnect() }
        text("Your connection stays local", 20f, true)
        text("DroidPier uses authenticated connections carried by Android debugging. No account, cloud relay, advertising, or analytics is required. Stop the desktop session before lending your computer or phone to someone else.")
        val version = packageManager.getPackageInfo(packageName, 0).versionName
        text("DroidPier Companion $version\nApache-2.0 · Independent open-source project", 14f)
        button("Project and help") {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/gysosin/droidpier")))
        }
        setContentView(ScrollView(this).apply {
            addView(column)
            setOnApplyWindowInsetsListener { view, insets ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars())
                    view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                }
                insets
            }
        })
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refresh()
    }

    override fun onResume() { super.onResume(); CompanionConnection.observe(observer); NotificationCommandBridge.observe(observer) }
    override fun onPause() { CompanionConnection.remove(observer); NotificationCommandBridge.remove(observer); super.onPause() }

    private fun refresh() {
        status.text = when (CompanionConnection.state) {
            CompanionConnection.State.DISCONNECTED -> "Not connected"
            CompanionConnection.State.CONNECTING -> "Connecting…"
            CompanionConnection.State.CONNECTED -> "Connected to DroidPier"
            CompanionConnection.State.RECONNECTING -> "Connection lost · reconnecting…"
            CompanionConnection.State.DISCONNECTING -> "Disconnecting…"
        }
        disconnect.isEnabled = CompanionConnection.canDisconnect
        val manager = getSystemService(NotificationManager::class.java)
        val component = ComponentName(this, NotificationBridgeService::class.java)
        val access = if (Build.VERSION.SDK_INT >= 27) {
            manager?.isNotificationListenerAccessGranted(component) == true
        } else {
            Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                .orEmpty().split(':').any { ComponentName.unflattenFromString(it) == component }
        }
        val notifications = manager?.areNotificationsEnabled() == true &&
            (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
        val accessStatus = when {
            !access -> "not allowed · optional"
            NotificationCommandBridge.isConnected -> "allowed · listener connected"
            else -> "allowed · waiting for Android to connect the listener"
        }
        permissions.text = "Connection notification: ${if (notifications) "allowed" else "not allowed"}\nPhone notification access: $accessStatus"
    }

    private fun openNotificationAccess() {
        if (Build.VERSION.SDK_INT >= 30 && launchSettings(Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    ComponentName(this, NotificationBridgeService::class.java).flattenToString()))) return
        if (!launchSettings(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))) openAppInfo()
    }

    private fun openAppInfo() {
        if (!launchSettings(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))) {
            launchSettings(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun openSettings(action: String, forApp: Boolean = false) {
        val intent = Intent(action)
        if (forApp) intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        if (!launchSettings(intent)) openAppInfo()
    }

    private fun launchSettings(intent: Intent): Boolean {
        if (intent.resolveActivity(packageManager) == null) return false
        return try { startActivity(intent); true }
        catch (_: ActivityNotFoundException) { false }
        catch (_: SecurityException) { false }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
