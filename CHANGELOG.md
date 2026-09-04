# Changelog

## Unreleased

Desktop shell improvements. Keyboard, launcher and window management.

- The desk search opens links through the facade instead of starting `xdg-open`
  from a widget. A widget that reaches the host directly cannot be rendered in
  the preview harness or covered by a test without launching a real browser,
  and it put scheme validation in the wrong place. The facade now refuses
  anything that is not `http`/`https` with a real host, so a `file:` or
  `javascript:` URL arriving from an application label or a notification body
  is turned away in one place rather than at each call site. Windows and macOS
  launchers are wired at the same time, ahead of those platforms shipping.
- Windows now carry a workspace, a zoom factor and an orientation, and the
  facade can set each. Nothing renders these yet; the capability lands first so
  the controls that use them are never buttons that cannot act.
- Fixed a latent bug rather than waiting for it: window state transitions went
  through two hand-rolled copy helpers that each listed every field by name, so
  any field added later was silently dropped on every move, raise and resize
  until someone remembered to edit both. They now share one `copyWith` on the
  model, with a test that a transition preserves what it was not asked to
  change.

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
- Every failure now says what to do about it. Twelve error codes existed and
  none of them was explained: a phone waiting for you to tap Allow, two phones
  connected at once and a version mismatch all arrived as one sentence and a
  code name. Wireless failures get more specific advice again, because a
  refused pairing code and a phone that was never reached need opposite
  answers.
- A failed start no longer shows the raw adb transcript. It can carry a device
  serial, a network address or a local path, so it is now copied deliberately
  rather than put on screen, with a reminder to read it before sharing.
- A failed start also offers to choose a different phone. Retrying is not the
  answer when the problem is that two are connected.
- A notification group folds after three, with a count on the sender. One
  chatty app no longer pushes every other sender off the screen.
- Alt+Shift+Tab steps backwards through open windows. The switcher also holds
  its order while open — during streaming the list could reorder underneath
  the highlight, so releasing Alt could focus a window you never picked.
- Turn a window portrait or landscape from its title bar.
- Taps land where you point them. Pointer input ignored the letterbox, so
  whenever the video and the window disagreed on shape every tap was offset,
  and a tap on a black bar landed in the middle of the app.
- A short first-run tour points out the launcher, window snapping, the taskbar
  and the tray, once.
- The boot screen names the phone it is coming up on, and how it is attached.
  With two phones on the desk the app connected to one of them and never said
  which; the transport is shown because the cable is what tells two of the same
  model apart. With more than one attached it also offers to choose, while the
  choice still matters rather than only after a failure.
- A window that is streaming but never receives a frame says so and offers to
  reopen, instead of showing a black rectangle with a lit Live badge for ever.
  A still app — a paused video, a page nobody scrolls — is deliberately not
  treated as broken, because it presents no frames either.
- Volume rows read Media, Ringtone, Notifications and Alarm rather than
  Android's raw stream keys, and are ordered by what people reach for instead of
  alphabetically, which had put Alarm above Media.
- Fixed: the taskbar overflowed its own width in two ways — the running-apps
  strip always claimed a fixed 420 pixels, and the media strip was admitted at
  exactly the width where it stopped fitting. The bar also measured the window
  rather than itself, so every width rule in it was evaluating against the wrong
  number.

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
