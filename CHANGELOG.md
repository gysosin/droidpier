# Changelog

## 0.1.0-beta.2 — 2026-09-01

Experimental Linux/Android preview. These changes are not in beta.1 downloads.

- One connection screen with local nearby-phone discovery, QR pairing, manual
  pairing, separate pairing/connection ports, and specific inline failures.
- Clipboard sharing defaults to off per connection. Unsupported access has a
  persistent explanation; runtime failures pause sharing and offer Retry.
- Companion startup tolerates Android reporting that its service is already
  stopped and avoids reinstalling an identical APK.
- Android setup separates connection notifications from optional notification
  access, refreshes Settings results, and explains restricted settings safely.
- Linux defaults to the tested direct streaming path; the legacy recording path
  remains an explicit fallback. Telemetry distinguishes decoded frames from frames presented. FFmpeg
  builds enable x86-64 assembly; the direct decoder checks compiled hardware
  support before selecting VA-API.

Performance work remains open: 60 FPS has not been restored. Physical Wi-Fi/QR
and the complete distribution/device matrix remain unverified. Read the release
notes for the checks performed and remaining limitations.

## 0.1.0-beta.1 — 2026-08-31

First public Linux/Android experimental preview. No stable release is available yet.

- DroidPier product identity and DroidPier Companion setup application.
- Signed companion release payload shared by desktop packages.
- Authenticated, user-requested disconnect without automatic session recovery.
- Linux packaging, release integrity checks, and public contribution documentation.

Windows/macOS remain in development. Desktop audio forwarding is unavailable.
Only mark a package released after its acceptance checklist passes.
