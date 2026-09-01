# Changelog

## Unreleased

Desktop shell improvements. Keyboard, launcher and window management.

- Keyboard shortcuts are defined once and documented by construction. Ctrl+/,
  F1, or `?` opens a cheat sheet listing every accelerator, rendered from the
  same list the dispatcher walks, so it cannot drift out of date.
- Launcher search ranks by match quality rather than the alphabet: literal
  prefix, then initials, then word start, substring and scattered letters.
  Initials mean "wa" finds WhatsApp, which a substring search cannot — the
  letters are not adjacent in the name.
- Search results weight by launch frequency and recency, so the drawer learns
  which apps are actually used. Habit reorders matches but never promotes
  something the query did not match.
- Search results are a ranked list with a selected row. Up and Down move it,
  Enter opens it, and typing returns to the top.
- Right-click an app to pin it above the rest. Pins survive restart.
- Right-click a window title bar for snapping to halves and quarters,
  Maximise/Restore, Minimise, Fullscreen, Close and Close others.
- Applications reopen where they were left, at the size they were, maximised
  if they were. Placements are clamped so a window saved on a larger monitor
  cannot restore beyond the edge of a smaller one.
- Empty, loading, error, no-match, results and pinned states of the launcher
  all carry golden coverage.
- Fixed: the auto-connect retry cancelled the window-move flush timer, a
  latent fault that would have shown up as a dragged window forgetting its
  position once the two paths could overlap.
- Appearance settings: choose an accent colour from six swatches, turn the
  frosted panels off for a flatter and cheaper desk, and reduce motion beyond
  whatever the system already asks for. Each section of Settings can be reset
  on its own.
- `Ctrl+Shift+P` opens a command palette: launch an app, switch to a window,
  or reach any shell surface by name.
- Fullscreen now says how to leave it, and keeps an exit control a
  pointer-move away. Previously `Esc` and `F11` both worked and neither was
  discoverable.
- Dragging a snapped window off its edge restores the size it had before it
  snapped, instead of sliding around the desk at half-screen size.
- `Ctrl+Shift+D` offers Copy diagnostics: a paste-ready report of build, phone,
  latency, throughput and per-window frame rate, carrying no device serial.
- Settings and the shortcut sheet show which build is running, including when
  it was built, so a fresh install can be told from a stale one.
- Fixed: a window-management helper allocated seven geometry objects per window
  per frame over the live video texture, which cost playback smoothness.
- Every corner radius is back on the token scale; several were one or two
  pixels off it, which is what made edges read as unfinished.

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
