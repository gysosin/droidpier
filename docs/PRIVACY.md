# Privacy

DroidPier does not require an account and contains no advertising, analytics, or
cloud relay. Its device integration runs locally through an authorized ADB
connection. The phone still uses its own network connection for its own apps.

In beta.2, clipboard sharing starts off for every connection and neither device
clipboard is accessed until the authenticated connection and explicit opt-in.
When enabled, clipboard synchronization transfers clipboard text between the
phone and computer. Notification access lets the companion send notification
content and supported actions to the connected desktop. App discovery transfers
application labels and icons; telemetry includes device state such as battery.
Grant these permissions only to a computer you trust.

While the connection screen is open, DroidPier browses local Android debugging
advertisements. Discovery does not authenticate or connect to every phone. QR
secrets are generated on the computer, expire after two minutes, and are discarded
on success or cancellation. Pairing credentials are sent to ADB through process
input, not command arguments. No external QR service receives them.

Session tokens and pairing codes are not application settings and must not be
retained in logs. The Android companion disables application backup. Android/ADB
may maintain their own debugging authorization and pairing records; revoke those
in Android settings when they are no longer needed.

Source downloads, GitHub links, badges and project metrics contact GitHub or the
named badge provider. The daily star chart stores aggregate counts only, not
profiles. No automatic silent software updater is included.

Before sharing a diagnostic or screenshot, remove personal app content, device
identifiers, notification text, clipboard data, addresses and pairing credentials.

Android requires the normal `CHANGE_NETWORK_STATE` permission for this network-based
connected-device foreground service. The companion declares it to run the session
service on Android 14 and later; it does not use it to silently change network settings.
