# UI roadmap

> **Reference parity, 2026-09-05.** Every desktop surface was compared against the
> reference implementation *running* — screenshots per page and per interaction at
> 1440×900 — and brought to it: boot, desk, dock, launcher, palette, sheet, switcher,
> window chrome and body states, diagnostics, control centre, notification centre,
> settings, connection, permissions, mirror, HUD, recovery, tour and the token sheet.
> `docs/UI_PARITY_PLAN.md` is the item-level record; the changelog lists what shipped
> and what was left out and why. The companion view (item 2.x's desktop counterpart)
> lives in the preview harness as a review surface, not in the product.
>
> **Status, 2026-09-04.** Tier 1 items 1.1–1.6 and structure item 4.4 are
> implemented; see the changelog. Item 1.3 shipped without "always on top",
> which has no API behind it. Item 1.5 shipped pinning via the context menu;
> drag-to-taskbar is deferred. Structure item 4.1, splitting `app_shell.dart`,
> is still open.
>
> **Workspaces (item 2.1) shipped.** `OpenDexFacade` carries
> `selectWorkspace` and `moveWindowToWorkspace`, windows hold a workspace, and
> the taskbar offers four numbered keys. Per-window zoom and window rotation
> landed at the same time, and `openUrl` moved link opening out of `lib/ui`.
>
> **The interface was reworked against `UI_REDESIGN_BRIEF.md`.** The Link
> Rail's connected state is on the desk, the launcher and the dock were
> recomposed, one bundled icon face replaced a mix of Material variants, panel
> shadows were matched to the brief, and four surfaces that were built but
> unreachable — the first-run tour, the phone mirror among them — were given
> doors. A design-token sheet (deliverable 15.1) renders every token from the
> tokens themselves, and the preview harness now offers all seventeen surfaces
> rather than six.
>
> **Not ported, deliberately:** the reference implementation's Android
> companion mock-up. It draws an imitation of the companion app's screens
> inside the desktop application, and §14 of the brief forbids drawing a fake
> phone screenshot anywhere. The companion's own UI work stays in §2 below,
> against the real APK.

Proposals for the desktop shell, the Android companion and the test surface that
guards both. Nothing here is a release commitment; see [Roadmap](ROADMAP.md) for
shipping plans. The committed visual language lives with the maintainers.

Scoring: **impact** is how much a user notices, **effort** is engineering days for
one person.

## 1. Desktop shell — what is missing

Snapping (halves and quarters), minimise, fullscreen, drag-resize, an app drawer
with substring search, a control centre, a notification centre and a taskbar all
exist today. The gaps below are the ones a DeX or Windows user will reach for and
not find.

### Tier 1 — high impact, low effort

| # | Feature | Why it matters | Where |
| --- | --- | --- | --- |
| 1.1 | **Fuzzy, ranked app search** with recency and launch-frequency weighting, arrow-key navigation and a visible selected row | The drawer is the most-used surface and currently does a plain `contains` match sorted alphabetically, so "wa" does not put WhatsApp first | `lib/ui/apps/app_drawer.dart` |
| 1.2 | **Keyboard shortcut cheat sheet** on `?` or `Ctrl+/`, generated from one shortcut registry | Shortcuts are hardcoded across `app_shell.dart` and invisible to users; a registry also makes them testable | new `lib/ui/shell/shortcuts.dart`, `lib/ui/shell/app_shell.dart` |
| 1.3 | **Window title bar context menu** — always on top, snap left/right, move to workspace, close others | Every desktop user right-clicks a title bar; nothing happens today | `lib/ui/workspace/app_window.dart` |
| 1.4 | **Restore window geometry per app** across sessions | Relaunching an app should reopen where it was, at the size it was | `lib/ui/workspace/window_model.dart`, `lib/bootstrap/desk_preferences` |
| 1.5 | **Drawer favourites / pinned apps row** with drag-to-taskbar | Turns a 400-app list into a five-app launcher | `lib/ui/apps/app_drawer.dart`, `lib/ui/desk/taskbar_bar.dart` |
| 1.6 | **Empty, loading and error states audited as first-class screens** | Golden tests exist for happy paths; failure paths are where the beta will be judged | `lib/ui/**`, `test/ui/*_golden_test.dart` |

### Tier 2 — high impact, medium effort

| # | Feature | Why it matters | Where |
| --- | --- | --- | --- |
| 2.1 | **Virtual desktops / workspaces** (2–4, `Ctrl+Alt+←/→`, taskbar indicator) | The single biggest "real desktop" gap; the window model already has z-order and geometry to key off | `lib/ui/workspace/workspace.dart`, `window_model.dart`, `lib/ui/desk/taskbar_bar.dart` |
| 2.2 | **Command palette** (`Ctrl+Shift+P`): launch app, switch window, toggle clipboard sync, run a device action, open settings | One surface replaces four; also the cheapest place to expose features that have no home | new `lib/ui/shell/command_palette.dart` |
| 2.3 | **Window switcher upgrade** — live thumbnails, most-recently-used order, hold-Alt cycling | The switcher exists but is a list; thumbnails are the reason people use Alt+Tab | `lib/ui/workspace/window_switcher.dart` |
| 2.4 | **Per-window zoom / DPI scale** and **rotation lock** | Android apps render at phone density; a 4K monitor makes them unreadable | `lib/ui/workspace/app_window.dart`, surface pipeline |
| 2.5 | **Screenshot and screen recording** of a single window or the whole workspace, saved to a chosen folder with a toast | Currently only an internal capture path exists; this is a top-five request for any mirroring tool | `lib/ui/workspace/workspace.dart`, `lib/ui/desk/control_center.dart` |
| 2.6 | **Multi-monitor awareness** — remember which display the shell opened on, keep snapping per-display | Desktop users have two screens; a shell that ignores that feels like a phone app | shell + platform runner |

### Tier 3 — polish and differentiation

| # | Feature | Why it matters | Where |
| --- | --- | --- | --- |
| 3.1 | **Picture-in-picture / always-on-top mini window** | Keep a video or chat visible while working | `lib/ui/workspace/app_window.dart` |
| 3.2 | **Theme system exposed** — accent colour, density (compact/comfortable), glass on/off, custom wallpaper | `dex_tokens.dart` already centralises this; the settings surface just does not expose it | `lib/ui/settings/desk_settings.dart`, `lib/ui/theme/` |
| 3.3 | **Notification centre actions** — inline reply, per-app mute, grouping, do-not-disturb | Half of a notification bridge is the ability to act without unlocking the phone | `lib/ui/desk/notification_center.dart` |
| 3.4 | **Onboarding tour** shown once after first successful connect | Beta users do not know snapping, `Ctrl+Space` or the drawer exist | new `lib/ui/boot/first_run_tour.dart` |
| 3.5 | **Connection health HUD** — FPS, latency, bitrate, decoder, with a one-click "copy diagnostics" | The README already publishes 39–47 FPS; make it observable in-app so bug reports arrive with numbers | `lib/ui/diagnostics/stream_diagnostics.dart` |
| 3.6 | **Motion and reduced-motion pass** — honour the platform reduce-motion setting throughout `dex_motion` | Accessibility requirement and a visible quality signal | `lib/ui/motion/dex_motion.dart` |
| 3.7 | **Localisation scaffolding** (`flutter-setup-localization`) even if only English ships | Retrofitting strings after 40 UI files is far more expensive than starting now | `apps/desktop/lib/**` |

## 2. Android companion — the APK needs a real UI

The companion is currently four activities and services with **no Compose
dependency and a single `styles.xml`** — one `drawable-nodpi/droidpier.png` is the
entire visual identity. It is the first thing a new user installs and the only
DroidPier surface they see on the phone.

| # | Work | Notes |
| --- | --- | --- |
| 2.1 | **Adopt Jetpack Compose + Material 3** with dynamic colour | Use the `android/skills` pack: `migrate-xml-views-to-jetpack-compose`, then `styles`, then `adaptive` |
| 2.2 | **Redesign `SetupActivity` as a stepped pairing flow** — Welcome → Permissions → Pair (QR or code) → Connected | Today it is a single 9 KB activity carrying the whole flow |
| 2.3 | **Live connection dashboard** — connected/disconnected state, desktop name, session duration, bytes transferred, big disconnect button | Users currently have no way to see the session from the phone |
| 2.4 | **Permission explainers** — one card per permission with what it is for and a direct settings intent | Permission denial is the top cause of a broken first run |
| 2.5 | **Ongoing notification redesign** — status, quick disconnect action, no full-screen intent | Foreground service notification is the companion's persistent UI |
| 2.6 | **Brand pass** — adaptive launcher icon, monochrome icon for themed icons, splash via the core-splashscreen API, dark theme parity | `drawable-nodpi/droidpier.png` is not an adaptive icon |
| 2.7 | **Match the desktop design language** — share the token values from `dex_tokens.dart` as a small Compose theme so both surfaces read as one product | |

Compose adds roughly 1.5–2.5 MB to the APK; verify against the R8 config with the
`r8-analyzer` skill before merging.

## 3. Testing — desktop, windows and the APK

The desktop has 47 test files including golden coverage, which is a strong base.
The gaps are the expensive kind: nothing exercises a running application, and no
platform other than Linux is built in CI.

| # | Work | Notes |
| --- | --- | --- |
| 3.1 | **Add `apps/desktop/integration_test/`** — boot, connect against `MockOpenDexFacade`, open two windows, snap, switch, close | The directory does not exist today; use `flutter-add-integration-test` |
| 3.2 | **Window manager test matrix** — snap to each edge and corner, drag between snap zones, restore, minimise/restore, fullscreen enter/exit, focus and z-order after close | `WindowSnap` and `WindowDisplayState` are pure logic and cheap to cover exhaustively |
| 3.3 | **Multi-window stress test** — 8+ windows, z-order integrity, taskbar/switcher consistency, frame budget | Extends `test/ui/idle_cost_test.dart` and `render_cost_test.dart` |
| 3.4 | **Windows CI job** — `windows-latest`, `flutter build windows`, `flutter test`, run `tool/build_windows.ps1` | CI is `ubuntu-22.04` only; the Windows target is built by nobody today |
| 3.5 | **macOS CI job** at least to `flutter analyze` + `flutter test` | Cheap early warning while the macOS bridge is in development |
| 3.6 | **Golden tests per platform** — goldens are rendered on Linux and will drift on Windows; tag platform-specific goldens or pin the test host | Decide before the Windows job lands, not after it goes red |
| 3.7 | **Companion instrumentation tests** — `androidx.test` + Compose UI tests for the pairing flow, run on an emulator in CI | Only one unit test file exists under `android/companion/src/test` |
| 3.8 | **Accessibility assertions in CI** — extend `test/ui/accessibility_test.dart` to every top-level surface, semantics labels and focus order | `flutter-improving-accessibility` skill |
| 3.9 | **Coverage gate** — `dart-collect-coverage` for the shared packages, publish LCOV, fail below the agreed floor | Set the floor in `CONSTRAINTS.md` via `constraint-driven-development` |
| 3.10 | **Mutation testing spot-check** on `packages/open_dex_protocol` | Confirms the protocol tests actually assert something |

## 4. Structure and clean code

| # | Work | Notes |
| --- | --- | --- |
| 4.1 | **Split `lib/ui/shell/app_shell.dart` (47 KB)** into shell scaffold, keyboard/shortcut registry, session state and overlay routing | Single largest maintainability risk in the UI; it is where every new feature currently lands |
| 4.2 | **Split `lib/ui/connect/connection_screen.dart` (38 KB)** into pairing steps mirroring the companion flow | |
| 4.3 | **Extract a `lib/ui/state/` layer** so widgets stop holding session state directly | `flutter-apply-architecture-best-practices` |
| 4.4 | **One shortcut registry** feeding both the handler and the cheat sheet (1.2) | Removes the scattered `LogicalKeyboardKey` checks in `app_shell.dart` |
| 4.5 | **Widen `tool/verify_source.py`-style checks to a file-size lint** — fail review above ~800 lines per widget file | Keeps 4.1 from recurring |
| 4.6 | **ADR per structural decision** in `docs/` | `documentation-and-adrs` |

## Suggested order

1. Tier 1 desktop items (1.1–1.6) — a week, and every one is user-visible.
2. Structure 4.1 and 4.4 — do these before Tier 2, or Tier 2 lands in a 47 KB file.
3. Testing 3.1, 3.2, 3.4 — the safety net for everything after.
4. Companion 2.1–2.3 — the phone side is the weakest surface in the product.
5. Tier 2 desktop, starting with virtual desktops (2.1) and file drag-and-drop (2.7).
