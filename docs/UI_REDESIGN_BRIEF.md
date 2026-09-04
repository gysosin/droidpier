# DroidPier — UI redesign brief

A complete, self-contained specification of the DroidPier desktop application:
what it is, every surface it has today, every state each surface must render,
the exact design tokens in use, and the features planned next that the new
design must already have a home for.

**This document is written to be handed to a UI generator whole.** It assumes
no knowledge of the codebase. Nothing here needs to be looked up elsewhere.

---

## 0. How to read this

| Marker | Meaning |
| --- | --- |
| **[SHIPPED]** | Exists in the product today. The redesign must cover it. Losing it is a regression. |
| **[PLANNED]** | Committed on the roadmap, not built. Design a place for it now so it does not get bolted on later. |
| **[BLOCKED]** | Wanted, but the backend has no API for it. Design the empty seat, not the control. |

Deliverables expected from the generator are listed in §15. Read §14
(anti-patterns) before generating anything — it is the shortest section and the
one that decides whether the result is usable.

---

## 1. The product in one page

**DroidPier — "Your Android. A bigger workspace."**

A desktop application that brings the apps on a physical Android phone into a
real desktop workspace on a computer. The apps run on the phone. The computer
provides the workspace: an app drawer, multiple freeform resizable windows,
full keyboard and mouse input, a taskbar, a notification centre, a clipboard
bridge, media transport, and phone hardware controls.

It is not a phone mirror and not a launcher-with-a-phone-in-it. It is a
**desktop environment whose applications happen to live on a phone**, and a
control surface for a **physical link between two machines**.

- **Connection:** USB (via ADB) or Wi-Fi (Android 11+ wireless debugging pairing).
- **Privacy:** no account, no cloud relay, no analytics, no advertising. Everything is local.
- **Licence:** Apache-2.0, open source, public repository.
- **Status:** `0.1.0-beta.2`, experimental Linux/Android preview. Windows and macOS in development.
- **Platform:** Flutter desktop. Linux (GTK) today; Windows and macOS next.

### The transport chain — the product's identity

Every connection is a five-stage handshake, and the interface exposes it
literally rather than hiding it behind a spinner:

```
ADB  →  Device  →  Agent :3698  →  Companion :3699  →  Applications
```

Two pieces of software are pushed to the phone during connection:

- **the shell agent** — a Java agent deployed through ADB, listening on device port **3698**, which performs restricted device commands.
- **the companion app** — a Kotlin Android app installed on the phone, listening on device port **3699**, which supplies status, permissions, notifications and media state.

This chain is the single most distinctive thing about the product and the
design's job is to make it legible. See §5.1 (the Link Rail).

### Known limits the UI must be honest about

- **No desktop audio forwarding.** Media transport controls exist; audio still comes out of the phone. The UI must never imply otherwise.
- **Frame rate is not 60 fps.** Measured 39–47 fps on the tested hardware. The UI reports rates rather than promising them.
- **DRM-protected and secondary-display-restricted apps may not stream.**
- **Behaviour varies by phone, Android version, and manufacturer.**

---

## 2. Who uses it

Technical desktop users: Linux users, developers, power users, people who
already know what ADB is or are willing to learn. They are comfortable with
serial numbers, ports and latency figures — **density is a feature, not a
burden**. They will judge the product by whether it tells them the truth when
something fails.

Design dials committed for this product:

```
VISUAL DENSITY   6/10   readouts are the point; do not spread things out
DESIGN VARIANCE  6/10   distinctive, not experimental
MOTION INTENSITY 5/10   motion shows state changing; it never decorates
```

---

## 3. Hard constraints that shape every decision

These are not preferences. Violating any of them breaks the product.

1. **App windows contain a live hardware video texture.**
   Never place a backdrop blur, a persistent animation, or a composited overlay
   over a streaming window. A blur re-samples its backdrop *every frame the
   backdrop changes* — over a 30–60 fps video that is a full-scene re-blur
   sixty times a second. This has already caused visible flicker and 72% host
   CPU in this codebase. The design must therefore ship **two rendering modes**
   (§4.3): a glass mode, and a flat matte mode used automatically whenever a
   window streams and manually when the user turns glass off.

2. **Nothing may allocate per frame, per window.** A helper that built seven
   geometry objects per window per build cost measurable playback smoothness.

3. **Fully keyboard operable.** Every surface. Visible focus ring in the accent
   colour, never clipped. See §9 for the complete accelerator map.

4. **Light and dark are both first-class.** Light is derived in the same colour
   family, not a washed-out dark theme and never warm paper.

5. **Reduced motion is honoured throughout.** The platform setting always wins;
   an in-app setting can only reduce motion further, never restore it.

6. **Tabular figures on every changing number.** Latency, throughput and frame
   rates update continuously and must not jitter the layout.

7. **Bundled fonts only.** Falling back to a system sans is the single largest
   cause of this UI reading as unfinished. Only glyphs the bundled faces
   actually contain — **the display and body faces do not include `→`**, so a
   navigation path is written in words ("open Developer options, then Wireless
   debugging"), never with an arrow.

8. **Size range.** Minimum usable ≈ 900×640. Design target 1280×800. Must
   remain correct to 3840×2160. Surfaces shed content at documented widths
   rather than overflowing (§5.6 lists the exact breakpoints in use).

---

## 4. Visual direction

### 4.1 The committed direction: **glass desk**

The surface language is **frosted glass over a lit blue-violet wallpaper**.
Almost every surface is white at 5–15%, blurred, with a one-pixel white edge.
Panels are not opaque fills — the desk shows through them. Radii are 8 / 12 /
16, because glass at a tight radius reads as sheet plastic.

**The redesign keeps this direction and raises it.** The brief is not "make it
glassy" — it already is. The brief is: make it read as a **professional
instrument** rather than a themed launcher. Reference points: precision
measurement equipment, a mixing desk, an aviation MFD, a well-made terminal —
not a consumer OS skin and not a crypto dashboard.

### 4.2 The identity mark

A **link between two bodies** — the phone and the desk, joined by a signal-blue
deck. A pier is where a vessel berths against solid ground; the deck is the
link this application exists to hold open. The two bodies are drawn in the muted
role colour; **the link is the one hot colour in the mark**, which is the same
rule the whole system follows.

### 4.3 Two rendering modes — both must be designed

| Mode | When | Treatment |
| --- | --- | --- |
| **Glass** | Default. No window is streaming, and the user has not turned glass off. | Translucent fill + backdrop blur + hairline edge + soft shadow. |
| **Matte** | Automatic whenever any window is streaming; also a user setting ("Frosted panels: off"); also the low-end-GPU path. | Same geometry, same hairlines, **no blur** — a slightly more opaque flat fill instead. |

Matte is not a degraded fallback. At these alphas the two are nearly
indistinguishable, and matte costs nothing. **Design both and make them look
like the same product.** Any panel that can end up above a live stream must be
legible without its blur.

### 4.4 Colour — semantic roles, never raw values

Two roles are reserved and must never be used decoratively:

- **`signal`** (blue) — link state and the primary action only.
- **`trace`** (emerald) — telemetry and data only.

#### Dark (primary surface)

| Role | Hex | Use |
| --- | --- | --- |
| `bg` | `#0B1120` | Window ground. Deep navy, never pure black. |
| `surface` | `#0F172A` | Panels, drawer, taskbar substrate. |
| `raised` | `#1E293B` | Cards, dialogs, menus. One luminance step above surface. |
| `line` | `#334155` | Hairlines, dividers, input borders. |
| `text` | `#F8FAFC` | Primary text. |
| `muted` | `#94A3B8` | Secondary text, disabled, captions. |
| `signal` | `#60A5FA` | Live link, primary action, focus ring. |
| `trace` | `#34D399` | Telemetry, throughput, charts. |
| `warn` | `#FBBF24` | Worse than asked for, but not a failure. |
| `fault` | `#FB7185` | Errors, destructive actions. |

#### Light (full parity, not an afterthought)

Every accent darkens. Blue-400 measures about 2.3:1 on light paper, which no
amount of taste makes readable.

| Role | Hex | Note |
| --- | --- | --- |
| `bg` | `#EEF2FB` | Cool paper, same blue family. **Never cream.** |
| `surface` | `#FFFFFF` | Panels. |
| `raised` | `#F8FAFC` | Cards, dialogs. |
| `line` | `#CBD5E1` | Hairlines. |
| `text` | `#0F172A` | Primary text. |
| `muted` | `#475569` | ≈ 7:1. |
| `signal` | `#1D4ED8` | Blue-700. |
| `trace` | `#047857` | Emerald-700. |
| `warn` | `#B45309` | Amber-700. |
| `fault` | `#BE123C` | Rose-700. |

#### The glass layer — alphas over a wallpaper, not opaque roles

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `fill` | `rgba(255,255,255,0.08)` | `rgba(255,255,255,0.72)` | Standard panel. Taskbar entries, widgets, drawer rows. |
| `fillStrong` | `rgba(255,255,255,0.20)` | `rgba(255,255,255,0.95)` | Hover and pressed. **Must out-contrast `fill`** — a hover that does not brighten is not a hover. |
| `fillSubtle` | `rgba(255,255,255,0.05)` | `rgba(255,255,255,0.54)` | Content nested inside another glass panel, where a second 8% layer would stack into opacity. |
| `substrate` | `rgba(15,23,42,0.65)` | `rgba(255,255,255,0.95)` | Dark glass for text-dense surfaces that must stay legible over a bright wallpaper: menus, dialogs, the app drawer. |
| `stroke` | `rgba(255,255,255,0.20)` | `rgba(15,23,42,0.12)` | Hairline on every glass edge. |
| `strokeStrong` | `rgba(255,255,255,0.40)` | `rgba(15,23,42,0.32)` | Focused-window ring and keyboard focus indicator. |
| `blur` | 24 px | 24 px | Backdrop blur sigma. |
| `bloom` | `rgba(255,255,255,0.15)` | `rgba(255,255,255,0.40)` | Radial highlight from the top-right corner of the wallpaper. |
| `vignette` | `rgba(0,0,0,0.30)` | `rgba(15,23,42,0.08)` | Darkening toward the bottom, so the taskbar has something to sit on. |

**Text over the wallpaper is the trap.** The lit corner of the gradient is
bright enough that muted text on it measures about 3.3:1. Anything text-dense —
the app drawer, menus, dialogs — sits on `substrate`, never on bare wallpaper.

#### Wallpapers (user-selectable, painted as diagonal gradients)

| Name | Stops |
| --- | --- |
| *Default* (dark) | `#1E3A8A` → `#1E40AF` → `#7C3AED` |
| *Default* (light) | `#BFD4F5` → `#C7D2FE` → `#DCC9F7` |
| Deep Midnight | `#0B2A3A` → `#0F766E` → `#1E3A8A` |
| Nordic Aurora | `#3B1F53` → `#7C3AED` → `#DB2777` |
| Volcanic Sunset | `#2E1065` → `#6D28D9` → `#9D174D` |
| Mist Canopy | `#1E293B` → `#6B5B95` → `#A78BBA` |
| Slate | `#0F172A` → `#1E293B` → `#334155` |
| Forest | `#052E16` → `#14532D` → `#166534` |

Each is a diagonal gradient (top-left to bottom-right) with a radial bloom from
the top-right and a vignette toward the bottom. Photographs cannot be shipped.

#### Accents (user-selectable, replaces `signal`)

Every accent carries a **darker light-mode value**; each is held to a 3:1 floor
against the background it actually appears on.

| Name | Dark | Light |
| --- | --- | --- |
| Signal *(default)* | `#60A5FA` | `#1D4ED8` |
| Phosphor | `#FBBF24` | `#92400E` |
| Trace | `#34D399` | `#047857` |
| Violet | `#A78BFA` | `#6D28D9` |
| Rose | `#FB7185` | `#BE123C` |
| Slate | `#94A3B8` | `#475569` |

### 4.5 Type — three roles, three faces

| Role | Face | Use |
| --- | --- | --- |
| **Display** | Space Grotesk | Screen titles, boot stages, empty-state headlines. Used sparingly. |
| **Body** | Public Sans | All prose, labels, buttons, menus. **Deliberately not Inter.** |
| **Data** | IBM Plex Mono | Serials, ports, latency, fps, adb output, error codes. |

*(Instrument Sans is also bundled and available as an alternative display face.)*

The mono is not a stylistic flourish — serials, ports and telemetry are machine
values and must read as such.

**Scale** (4 px grid):

| Slot | Size / weight | Line height |
| --- | --- | --- |
| displayLarge | 44 / 600 | 1.2 |
| displayMedium | 38 / 600 | 1.2 |
| displaySmall | 32 / 600 | 1.2 |
| headlineLarge | 28 / 600 | 1.2 |
| headlineMedium | 24 / 600 | 1.2 |
| headlineSmall | 20 / 600 | 1.2 |
| titleLarge | 20 / 500 (display face) | 1.2 |
| titleMedium | 16 / 500 (body) | 1.45 |
| titleSmall | 14 / 500 (body) | 1.45 |
| bodyLarge | 15 / 400 | 1.45 |
| bodyMedium | 13 / 400 | 1.45 |
| bodySmall | 11 / 400, muted | 1.45 |
| labelLarge | 13 / 500 | 1.45 |
| labelMedium | 12 / 500 | 1.45 |
| labelSmall | 11 / 400, muted | 1.45 |
| **data** | 13 or 11, mono, **tabular figures mandatory** | 1.4 |

Display carries `letter-spacing: -0.2`. Every text slot must be defined — an
undefined slot silently falls through to a font that is not bundled, which
renders as tofu boxes.

### 4.6 Space, shape, elevation

- **4 px base unit.** Spacing tokens: `4, 8, 12, 16, 24, 32, 48`.
- **Radii:** **8** controls, chips, small icon buttons · **12** rows, list items, buttons, cards · **16** dialogs, menus, panels, windows, the taskbar · **999** fully round (status dots, gesture pill, toggle tracks). There is no 4 and no 24 — four steps, and every corner uses one of them.
- **Strokes:** hairline `1`, focus ring `2`, link-rail collapsed trace `4`.
- **Elevation is a luminance step plus a hairline, never a drop shadow.** The one exception: a glass panel needs a soft shadow to separate from the wallpaper — `rgba(0,0,0,0.35)`, blur 32, offset `0 12`. Panels flush against a screen edge suppress it, where a shadow reads as a seam.
- **Every corner radius must land exactly on the token scale.** Several were one or two pixels off it, and that is precisely what made edges read as unfinished.

### 4.7 Hit targets

This is a pointer-driven desktop application, so the governing standard is
**WCAG 2.2 SC 2.5.8 Target Size (Minimum) — 24×24**. Android's 48 dp rule is a
*touch* guideline and does not apply.

| Token | Size | Use |
| --- | --- | --- |
| `minimum` | 24 | Absolute floor. Nothing interactive may be smaller in either dimension. |
| `comfortable` | 32 | Small icon controls sitting among others. |
| `primary` | 44 | Buttons, fields, anything aimed at first. |

Where a larger target is free, take it.

---

## 5. Complete screen inventory

Fifteen surfaces exist today. Every one must survive the redesign, and every
one must be reachable — two screens in this codebase have already been orphaned
by refactors, rendered in the tree with nothing able to open them.

### 5.1 The Link Rail — the signature element **[SHIPPED]**

One persistent instrument, three forms, one object the user learns once. It
renders the real transport topology, driven directly by connection state rather
than by a UI-local guess. **This is the only place the design spends boldness.
Everything else stays quiet.**

**Stations, in order:** `ADB` · `Device` · `Agent :3698` · `Companion :3699` · `Applications`

| Form | When | Rendering |
| --- | --- | --- |
| **Expanded** | Boot | Full-height vertical rail. Each stage is a *station on a rail*, not a row in a list. Segments between stations fill from the top as the stage above completes. |
| **Collapsed** | Connected | A 4 px horizontal trace carrying live latency, throughput and frame rate. Same instrument, third state — the one seen most, so it stays quiet. |
| **Recovery** | Link lost | Re-expands to the stage that failed. The reconnect watchdog is visible as motion along the rail, so waiting is legible instead of opaque. |

**Station states — the three must never look alike**, because the rail's whole
job is showing which one you are waiting on:

| Status | Node |
| --- | --- |
| `pending` | Hollow ring, muted. |
| `active` | Haloed and breathing (a slow pulse). |
| `complete` | Filled and calm, in `signal`. |
| `failed` | Filled in `fault`, segment below unfilled. |

Each station may carry a one-line detail string beneath its label.

**Performance rule, learned the hard way:** the collapsed trace must **not** run
a perpetual gradient pulse. It once ran a 2.6 s repeating animation for the
entire connected session, forcing the whole tree — glass panels and a live video
texture included — to re-composite at 60 fps, measured at ~72% host CPU. The
band distinguishes live from down **by colour**, and the numbers beside it change
on their own. Design it static.

### 5.2 Boot screen **[SHIPPED]**

The whole window until the link is up. There is nothing else to do until it
finishes.

**Composition — two columns on a wide window:**

- **Left:** masthead (`DROIDPIER` / `LINK`, held at the top edge like an instrument's faceplate label, not floating with the content); the intent headline; the device line ("Android 13 · USB" — which phone, over what).
- **Right:** the Link Rail, expanded, in its own panel so it reads as an instrument mounted on a bench rather than a list of steps floating in the page.
- **Below both:** a bench readout strip in mono — the machine's own account of the link, tabular so the numbers do not jitter.

Narrow windows stack the same pieces in the same order.

**States:**

| State | Headline | Action |
| --- | --- | --- |
| Idle, no phone | "Plug in your phone" | **Connect phone** |
| Idle, one phone | "Bringing up the link" | *(none — connecting is a state, not a button)* |
| Working | "Working…" + live stage detail | *(none)* |
| More than one phone | "Choose a phone" | **Connect phone** (opens the connection screen) |
| Ready | "Your desk is ready" | **Open workspace** |
| Failed | "The link did not come up" + specific guidance (§8) | **Try again** · **Choose a phone** · **Copy technical details** |

**Copy technical details** puts a paste-ready block on the clipboard rather than
on screen, with the warning *"Technical information about this computer and the
phone. Read it before sharing."* — a raw adb transcript can carry a device
serial, a network address or a local path.

**Auto-connect rule:** the app connects on its own only when there is no
question to answer — exactly one authorised phone, and no session established
yet. Once a session has come up, a later disconnect is a deliberate act: the
app returns to the boot screen and **waits for the person**. Any manual action
(opening the picker, pressing retry) stands auto-connect down permanently.

### 5.3 The desk — the home screen **[SHIPPED]**

A desktop environment should look inhabited, so this is a real desktop.

**Layer order, deliberately** (bottom to top):

1. **Wallpaper** — gradient + bloom + vignette.
2. **Desk furniture** — search bar, app icons, clock, right-hand widget column.
3. **The workspace** — app windows, inset by the taskbar's height so a window cannot be dragged out of reach.
4. **The taskbar** — above the windows. Every desktop keeps its taskbar on top; this one did not, and maximising an app hid it.
5. **Popovers** the taskbar opens — control centre, notification centre.

**Furniture:**

| Element | Position | Behaviour |
| --- | --- | --- |
| Search bar | Top-left, translucent pill with a drawn multicolour Google mark | Submitting opens the query in the desktop's default browser |
| App icons | Left column, filling downward from y≈190 | The few apps you reach for without thinking. The drawer holds everything and has search. |
| Analog clock | Top-right, 300 px, **bare** — no card, lifted off the wallpaper by a soft shadow | Drawn, not an image. Dark disc, tick marks, white hour/minute hands, **`signal`-coloured second hand**. Ticks live once a second and repaints only itself. Hidden below 860 px width. |
| Widget column | Right, 320 px wide, hanging below the clock | Now Playing · Phone · Notifications. Hidden below 1180 px wide or 760 px tall. |

**Recede behaviour:** when an Android window takes focus, the furniture drops to
50% opacity so the desk stops competing with the app in use. Only a window that
is *actually streaming* counts — a window passing through `starting` or
`reconnecting` would otherwise make the desk blink.

#### Desk widgets **[SHIPPED]**

| Widget | Content |
| --- | --- |
| **Now playing** | Artwork, title, artist, and a transport (previous · play/pause · next). Empty state: "Nothing playing". |
| **Phone** ("Desk mode") | Labelled meters, a radio row (Wi-Fi / USB), and a device identity line ("Android 15"). **Only battery has real data today** — CPU, memory and storage are omitted rather than faked. A null value renders the track with no fill and reads `—`. A radio whose state was never reported is drawn faintest, so the widget never claims a radio is off when it does not know. |
| **Notifications** | The three most recent, plus a count. Empty: "Nothing new." Blocked: "Allow notification access on the phone." |

The desk widgets **report state and do not change it**. A widget you can
accidentally toggle while glancing at it is worse than one that stays still —
every control that changes the phone lives in the control centre instead.

### 5.4 Taskbar and system tray **[SHIPPED]**

A **segmented bar**, not one pill — each cluster is a floating rounded-glass
segment, so the bar reads as clean segments rather than a row of touching
borders.

| Cluster | Position | Contents |
| --- | --- | --- |
| Left | Left | **Nav pill** (Menu · Home · Back · Search — Android navigation keys injected into the focused window's display; enabled only when a window has focus) · hairline divider · **running-apps strip** (scrolls; each entry focuses, right-click closes; minimised entries carry a dimmed running dot) · **media pill** |
| Centre | Centred | **Apps grid button** — "Your apps". Opens the launcher. |
| Right | Right | **System tray** |

**System tray, left to right:** notification **bell** with a count badge ·
**status cluster** (Wi-Fi glyph when on, charging bolt in `signal` when
charging, battery glyph, battery percentage in mono — opens the control centre)
· **settings gear** · **clock** (`h:mm AM/PM` in mono above, `3 Sep` in smaller mono below; opens
the control centre) · **fullscreen toggle**.

**Responsive shedding — the bar sheds rather than overflows:**

| Threshold | What is dropped |
| --- | --- |
| < 1100 px | Media strip (the dock's own transport reaches the same controls) |
| < 760 px | Nav pill |
| Narrow tray | The date goes first (the time is what people glance at), then the fullscreen toggle (F11 does the same job and the title bar carries its own control) |

Reserved band at the bottom: **72 px**. A maximised window stays above it.

### 5.5 App launcher / drawer **[SHIPPED]**

Full-bleed, painting its own blurred scrim over the desk. A real device reports
on the order of eighty applications, so the drawer is built around **finding**
one rather than browsing all of them.

- **Search field holds focus on open.** Typing filters; Enter launches the top match.
- **Ranked search, not alphabetical.** Match tiers, strongest first: literal prefix → **initials** → word start → substring → scattered letters. Initials mean typing `wa` finds *WhatsApp*, which a substring search cannot — the letters are not adjacent in the name.
- **Habit weighting.** Launch frequency and recency reorder matches, bounded below one tier step so habit **breaks ties but never overrules the query**. Nothing the query did not match is ever promoted.
- **Keyboard list.** Up/Down move a selected row, Enter opens it, typing returns to the top. **Selection must out-contrast hover, which must out-contrast rest** — otherwise moving the mouse over a list being driven by keyboard makes it impossible to tell where Enter will go.
- **Pinned row.** Right-click an app → *Pin to top* / *Unpin from top*. Pins survive restart and sit in their own section above everything else.
- **Sections:** Pinned · User apps · System apps.
- **Empty query** shows everything, alphabetical, in a non-scrolling grid of tiles per section inside one scroll view.

**States:** loading (skeleton grid mirroring the final tile layout exactly, no
layout shift) · empty ("No apps yet — connect a phone and its apps will appear
here", with **Look again**) · no match ("Nothing matches "xyz" — try a shorter
search", with **Clear search**) · results · error.

### 5.6 The workspace and app windows **[SHIPPED]**

Freeform, overlapping, independently minimisable windows — **not tabs**. Two
apps must be simultaneously visible, movable and resizable, which tabs cannot
satisfy.

**Ownership rule:** the backend owns geometry, z-order, display state and focus.
The UI **sends intent and renders what comes back**. The single exception is a
window mid-drag, whose geometry stays local until the drag ends so the frame
tracks the pointer instead of stuttering against stale echoes.

#### Window chrome

- **Title bar** — chrome the desk owns. The body belongs to the Android app. **Dragging is title-bar only**; a drag started in the body would steal input the app needs.
- **Title bar contents:** app label (left) · **Live badge** (right, a `trace`-coloured dot + "Live") · rotate · fullscreen · minimise · maximise/restore · close.
- **The Live badge says whether the stream is alive, not how fast.** A bare rate beside an app name reads as a performance grade and was twice mistaken for a fault. The rate is available on hover and in the diagnostics panel, where a number is expected to be a number. Zero deliberately still reads as live — Android emits frames on change, so a paused video and a dead pipeline look identical from this side.
- **Focused window:** ring at `strokeStrong` (white 40%), border white 30%. **Unfocused:** ring white 15%, border white 20%. Focus is distinct from z-order — a window can be raised without focus (from the dock) and focused without moving in z.

#### Window interactions

| Action | Behaviour |
| --- | --- |
| **Click anywhere** | Focuses and raises |
| **Drag** | Title bar only. Clamps at the workspace edge — the title bar always stays reachable |
| **Resize** | Eight handles, **8 px hit slop outside the frame** so a 1 px border is still grabbable. Minimum **240×180** |
| **Snap** | Drag to an edge for a half, to a corner for a quarter, to the top to maximise. **Preview overlay before release**, so a snap is never a surprise. Dragging a snapped window off its edge restores its pre-snap size |
| **Maximise** | Fills the workspace minus the taskbar. Double-clicking the title bar toggles |
| **Minimise** | Leaves the workspace, stays in the dock with a dimmed running dot |
| **Fullscreen** | Edge-to-edge: only that window's video, filling the monitor, no desk, taskbar or title bar. A thin chrome bar appears on pointer-move carrying **Exit fullscreen** and the hint *"Press Esc or F11 to leave fullscreen"* |
| **Close** | Ends the session, dock entry disappears. **No confirmation** — the Android app keeps running on the phone, so nothing is destroyed |
| **Right-click title bar** | Context menu (below) |
| **New window placement** | **Cascaded, not centred.** Two apps opened in a row must both be visible; centring would stack them exactly |
| **Remembered placement** | An app reopens where it was left, at the size it was, maximised if it was. Per package, clamped into the current workspace so a window arranged on a large monitor cannot restore beyond the edge of a smaller one. **Minimised is deliberately not remembered** — a window you come back to should not reopen hidden |

#### Title-bar context menu

Snap left half · Snap right half · each of the four quarters · Maximise/Restore ·
Minimise · Fullscreen · **Portrait/Landscape** · Close · Close others.

The orientation entry **names where it will go, not where it is**. It inverts
the *content* aspect, not the frame's — swapping the frame's own width and
height would leave the video letterboxed by exactly the title bar's height.
Entries appear only where the API can perform them: there is no always-on-top
and no move-to-workspace, so neither is offered even in a disabled form.

#### Every window state must render something honest

| Status | Frame shows |
| --- | --- |
| `starting` | Skeleton tinted at the app's own colour, label "Opening…" |
| `streaming` | The live surface |
| `streaming`, **surface not yet arrived** | The skeleton — **never an empty rectangle**, which reads as a broken app |
| `streaming`, **no frame ever painted** | "No video is arriving" + *"The app is running on the phone and this window has a place for it…"* + **Reopen**. A black rectangle with a lit Live badge is indistinguishable from an app showing black |
| `suspended` | **Last frame dimmed under a scrim**, label "Paused" — never a blank box; a paused window that goes black is indistinguishable from a crashed one |
| `reconnecting` | Last frame dimmed, with the rail's travelling trace, label "Reconnecting…" |
| `failed` | `fault`-bordered frame, "This app stopped" / "The window closed unexpectedly.", **Try again**, **Copy technical details** |
| `closed` | Removed from the workspace entirely |

**Distinguishing "still" from "dead" is subtle and matters.** A paused video and
a page nobody scrolls both present zero frames per second and are working
perfectly. No amount of waiting separates them. What separates them is whether
the window has *ever* painted — so that is what is tracked, and a rate that has
not been reported yet is not the same as a reported zero.

**Pointer accuracy:** input must account for letterboxing. When the video and
the window disagree on shape, an unadjusted tap lands offset, and a tap on a
black bar lands in the middle of the app.

### 5.7 Window switcher (Alt+Tab) **[SHIPPED]**

Opens on the first Alt+Tab press and stays while Alt is held; commits on
release. Escape cancels the switch rather than committing it.

- Cards for every open window, in **z-order** — repeated presses read as "the window behind this one" rather than an arbitrary list.
- Each card shows the app label and its state: Running · Opening · Paused · Reconnecting · Minimised · Stopped.
- The first press lands on the window *beneath* the current one, not the one already focused.
- **The order is frozen when the switcher opens.** The shell rebuilds on every telemetry snapshot — continuously during streaming — so a list re-derived per rebuild could reorder underneath the highlight, and releasing Alt would focus a window the person never picked. A window that closes mid-hold drops out rather than leaving a stale entry.
- **[PLANNED]** live thumbnails, most-recently-used ordering.

### 5.8 Control centre (quick settings) **[SHIPPED]**

Anchored above the tray, which is where it opens from. **Every control that
changes the phone rather than the desk lives here.**

- **Two wide pills** at the top: Wi-Fi, Bluetooth.
- **Circular toggle grid** with labels beneath: Airplane · Rotation lock · Torch · Mobile data · Location.
- **Volume sliders**, one per stream the phone reports, in this order: **Media · Ringtone · Notifications · Alarm · System · Voice call**, then anything unanticipated. Android reports raw keys (`music`, `ring`, `voice_call`) — never print those; nobody calls the media volume "music", and "ring" is a verb.
- **Shared clipboard** — a switch, **off by default per connection**, plus every reason it may not be available. Turning it on is what lets the desk read what is on the phone, so it is an explicit opt-in.
- Footer links: **Phones…** · **Settings…**

**The panel's banner states, in priority order.** `calm` styling (no fault
colouring) for the ones that are states rather than failures — painting a
not-yet-reported capability red teaches people to ignore red:

| Condition | Banner |
| --- | --- |
| Agent unavailable | "The phone is not connected, so these controls cannot reach it." |
| Agent starting | "The phone is still connecting. These controls will work once it finishes." |
| Agent reconnecting | "Reconnecting to the phone. These controls will work once the link is back." |
| Restricted | "Some controls may be restricted by Android." |

**Clipboard sub-states**, each persisting for as long as it is true — none of
these raises a transient toast, so a paused sync is visible next time the panel
opens rather than only in the second a toast appeared:

- Off: *"Off — nothing is read from the phone"*
- Unknown: *"This phone has not said whether it can share a clipboard yet…"*
- Unavailable: *"This phone will not share its clipboard, so the desk cannot read it."*
- Paused after a desktop failure: the reason + **Retry**
- Content: *"Nothing copied yet"* / the text / *"An image is ready to paste"*

**Disabled-control rule:** the switch is disabled until the link is up and the
phone has said it can share at all. **A live switch that fails when pressed is
worse than a dead one that says why.**

Also: Wi-Fi carries a guard — *"Wi-Fi must stay on for wireless debugging"* —
when the session itself depends on it.

### 5.9 Notification centre **[SHIPPED]**

Opened from the tray bell. The desk widget shows three and a count, which is
right for a glance and useless for reading them.

- **Grouped by sender.** A group folds after three with a count badge on the sender — one chatty app must not push every other sender off the screen. **Show N more from {sender}** / **Show less**.
- Per item: **Dismiss**, and clicking activates it on the phone.
- **Clear all** in the header.
- **The phone stays the source of truth.** Dismissing does *not* remove the item locally — it asks the phone and waits for the item to leave the snapshot. Removing it optimistically would show a notification as gone that is still sitting on the phone's shade. While the request is in flight the row says "Dismissing…" rather than going still.

**States:** loading · empty ("Nothing new") · **blocked** ("Notifications are
turned off — the phone has not granted notification access, so nothing reaches
the desk", with **What the desk can use…** opening the permissions panel) ·
error.

### 5.10 Connection screen **[SHIPPED]**

**The one place a phone is added and chosen.** It replaces an older design
where a phone list had a pairing dialog stacked on top of it — that asked the
person "which phone?" before they had one, then buried the way to get one
behind a second modal.

Both halves are on screen at once:

**Left — Phones.** *"Plugged in over USB, or already connected over Wi-Fi."*
Every transport ADB can see. Per row: name, model, `Android 13`, connection
kind (USB / Wi-Fi), status (**Ready** · **Tap "Allow" on the phone** ·
**Offline**), and per-row **Connect** / **Disconnect**. Header action: **Look
again**.

**Right — Add over Wi-Fi.** *"Android 11 and later. Wireless debugging must be
on."* Three **segments**, not steps, because they are genuinely different
routes:

| Segment | What it is |
| --- | --- |
| **Nearby** | Advertisements heard on the network. **Hints only** — nothing here proves a phone is paired or is even the phone it claims to be, so nothing is ever attempted automatically. Each entry says what it is offering: *"Offering to pair — needs the code from the phone"* or *"Offering a debugging connection"*. Actions: **Pair…** / **Connect**. |
| **QR code** | The phone scans the computer. Android's own *Pair device with QR code* screen is the scanner; DroidPier only displays the payload. **Codes expire in about two minutes** with a live countdown, then **New code**. |
| **Manual** | Phone address, pairing port, and the six-digit pairing code. *"Leading zeros count — 004821 is a different code from 4821."* *"It is used once and is not kept."* |

**Pairing progress** is its own sequence: Pairing… → *"Paired. Finding the
connection…"* → **Connected over Wi-Fi**, with a distinct branch when the
connection port cannot be worked out automatically: *"Paired. DroidPier could
not work out the connection port on its own"* + a **Connect port** field +
*"The connect port is not the pairing port — check the number Android is
showing."* Android advertises the debugging port separately from the pairing
port, and this is the single most common wireless failure.

**Lifecycle rule:** discovery runs for exactly as long as this screen is open —
started on open, stopped on close along with any pairing in flight. Every route
in and out (boot screen, Settings, Escape, Close) is therefore covered.

**Disconnect confirmation:** *"Disconnect drops this computer's link to a phone.
It does not unpair — the phone keeps the pairing."*

**States:** searching ("Looking for phones…") · empty ("No phones found — turn
on USB debugging and choose "Look again", or add one over Wi-Fi on the right")
· ADB unavailable ("DroidPier could not start ADB on this computer.") ·
discovery unavailable ("Network discovery is not available on this computer.
Pairing by QR code or by hand still works.") · working ("Talking to the phone…").

### 5.11 Settings **[SHIPPED]**

Grouped rows. **Only rows this UI can genuinely act on are present** — a switch
that does nothing when flipped is worse than an absent one, and this product
shipped that mistake once already with permission buttons.

| Group | Rows |
| --- | --- |
| **Appearance** | **Theme** (System / Light / Dark — *"Dark reduces glare on external panels."*) · **Accent** (six swatches, each previewing its value for the theme currently on screen) · **Wallpaper** (swatch row, selected carries a ring) · **Frosted panels** (switch — *"Blurs the desk behind panels. Turn off for a flatter, cheaper desk."*) · **Reduce motion** (switch — *"Skips the entrance animations. Already on if the system asks for it."*) |
| **Desktop mode** | **Window snapping** (switch — *"Halves and quarters at screen edges."*) |
| **Phone** | **Manage phones** (*"Switch phone or pair a new one."*) · **Permissions** (*"What the phone has granted the desktop."*) · **Disconnect** (*"End the session with {phone}."*) |
| **Scope** | Note row: *"How the desk behaves. Your phone's own settings stay on the phone."* |
| **About** | Product name, tagline, **build version including build date** (so a fresh install can be told from a stale one), **Licences** (*"Original code is Apache-2.0. Bundled components keep their own licences."*), and the note that **desktop audio forwarding is not implemented** |

**Each group can be reset on its own.**

**[BLOCKED]** — resolution, brightness, keep-phone-screen-on, phone-as-second-surface.
These need backend commands and an external-display concept that does not exist
yet. Design the seats; do not draw the controls.

### 5.12 Permissions panel **[SHIPPED]**

*"What the desk can use."* — *"Everything here is optional. Turn on only what
you want."*

A capability the phone has not granted **is not an error** — it is a feature
that is off, with a way to turn it on. Each row states what the capability does
*for the person*, its current grant, and the one action that changes it.

| Capability | Description |
| --- | --- |
| **Notifications** | "Show your phone's notifications on the desk." |
| **Media controls** | "Play, pause, and skip from the desk." |
| **Audio** | "Hear your phone through this computer." |
| **Clipboard** | "Copy on one device, paste on the other." |
| **Calls** | "Answer and end calls without picking up the phone." |

**Grant states:** granted ("On") · denied ("Off", action **Turn on**) ·
requiresSettings ("Needs phone settings", action **Open on phone** — offered
*only* for notifications, the one capability where that intent is verified
against a real device) · unavailable ("Not on this phone").

**A control that does nothing is worse than no control.** Permission buttons
were once wired to an empty callback because the facade had no command behind
them. Prefer guidance text ("Allow on the phone", "Turn on from the phone")
over a button that lies. **Nothing here dead-ends.**

**States:** loading (skeletons mirroring the real rows so nothing shifts) ·
empty ("Nothing to allow yet — connect a phone and its capabilities will appear
here").

### 5.13 Recovery overlay **[SHIPPED]**

Covers everything at ~92% opacity. Nothing else is usable while the link is
down, and pretending otherwise invites dead clicks.

| Phase | Headline | Body | Actions |
| --- | --- | --- | --- |
| `detecting` | "Checking the connection…" | — | — |
| `reconnecting` | "Reconnecting…" | attempt count | **Reconnect** · **Disconnect** |
| `restartingServices` | "Restarting phone services…" | "Keep the cable connected." | — |
| `recovered` | "Reconnected" | "Your workspace is back." | — |
| `failed` | "Phone disconnected" | "Check the cable, then choose "Reconnect"." | **Reconnect** · **Disconnect** |

**Hold-back rule:** the overlay must not toggle on the raw phase. It once
appeared and vanished the instant the phase moved, so a transport dipping in and
out of recovery flashed the entire screen. Once shown it stays for a minimum
duration.

**Windows must survive recovery and restore afterwards.** They are not torn down.

### 5.14 Diagnostics **[SHIPPED]**

Two separate surfaces, deliberately.

**Health HUD** (`Ctrl+Shift+H`) — a small, quiet readout pinned above the
taskbar. Off by default: it sits over live video, and a permanent overlay on a
surface whose whole point is the picture has to be asked for.

- Frames per second, link latency, throughput, and which window the rate belongs to (an unattributable rate answers "how fast" without answering "what").
- **Graded:** good / fair / poor / unknown, against the configured rate. **A low grade is a reading, never an accusation** — a still screen legitimately presents few frames.
- **Paints flat colour and text and nothing else.** No blur, no shadow, no animation — each would cost a composite over the very stream it is reporting on, which would make the readout the reason the number drops.

**Stream diagnostics** (`Ctrl+Shift+D`) — a panel. *"Deliberately not a debug
dump. Every row is something a person could act on."*

- Per window: what the phone is sending, at what size, and what went wrong last.
- **Three frame rates shown together** — produced, presented, dropped — so the gap between them is the thing you read first. These were once conflated into one number: the pipeline produced 72 frames a second and put 15 on screen, and every figure anyone quoted was the 72. **The widget will not render a lone figure**; if only one rate is known it still says which one.
- **Recently closed** — one line per window that has gone (last 8, most recent first), because a closed window leaves the state entirely and by the time someone asks "where did it go?" there is nothing left to inspect.
- **Copy diagnostics** — a paste-ready report of build, phone, latency, throughput and per-window frame rate, **carrying no device serial**.
- Footer: "Ctrl+Shift+D to close".

### 5.15 Command palette **[SHIPPED]**

`Ctrl+Shift+P`. One searchable list of everything the shell can do — the
cheapest home for every feature with no natural surface of its own.

Groups: **APPS** (launch any app) · **WINDOWS** (switch to any open window) ·
**DEVICE** · **SHELL** (Open settings · Show keyboard shortcuts · Toggle stream
diagnostics · Toggle the health readout · Open the app launcher · Manage phones
· Permissions).

Shares its matcher with the drawer, so typing behaves identically in both.
Rebuilt on every open rather than cached, so a command can never outlive the
thing it acts on — an uninstalled app or a closed window is simply absent.

### 5.16 Keyboard shortcut sheet **[SHIPPED]**

`Ctrl+/`, `F1`, or a bare `?` when nothing is typing. **Generated from the same
list the dispatcher walks**, so it cannot drift out of date. Grouped: Launcher ·
Windows · Session · Diagnostics. Footer: *"Esc closes whatever is open, one
layer at a time."* Also shows the running build.

### 5.17 First-run tour **[SHIPPED]**

Four steps, shown once, over the desk after the first successful connect —
never over the connection screen, where it would describe surfaces the person
cannot see yet.

1. **Find an app by typing** — `Ctrl` `Space`
2. **Arrange windows by dragging** — drag a title bar to a screen edge
3. **Switch between what is open** — `Alt` `Tab`
4. **Your phone, from the desk** — the tray carries clipboard sharing, volume and notifications

Ends on *"Press ? any time for every shortcut"*. **Skip** · **Next** · **Done**.

*Design note:* a spotlight cut-out over each real widget was the original plan
and was rejected — two of the four targets are not guaranteed to be on screen
(there may be no window open), and **a spotlight over an empty desk teaches
less than a sentence does**.

### 5.18 Phone mirror **[BUILT, NOT PLACED]**

A drawn representation of the phone as hardware — frame, status bar, punch-hole
camera, radios, battery, app grid, four-app dock, gesture pill — docked
bottom-right. It renders the *device* faithfully and says plainly, inside the
frame, that the live screen is not available. **It does not fake a screenshot.**

This component exists and is tested but is not currently placed on the desk.
The redesign should either give it a home or retire it explicitly.

---

## 6. The data the UI renders

Everything on screen comes from one immutable snapshot, streamed continuously.
This is the complete field list — the design must not invent a value that is
not here, and must not omit one that is.

```
Snapshot
├── boot            phase, progress 0–1, message, stages[], error
│                   phases: idle · startingAdb · discoveringDevice · connectingDevice
│                           · startingServers · deployingAgent · installingCompanion
│                           · awaitingHandshakes · loadingApplications · ready · failed
│                   stage:  id, label, status (pending|active|complete|failed), detail?
├── devices[]       id, name, model?, androidVersion?, connectionKind (usb|wifi),
│                   status (authorized|unauthorized|offline)
├── selectedDevice
├── applications[]  packageName, label, iconPng?, isSystemApp
├── windows[]       id, application, status, displayId?, isFocused, geometry (x,y,w,h),
│                   displayState (normal|minimised|maximised), zOrder,
│                   surface? (textureId + pixelSize),
│                   producedFps?, presentedFps?, droppedFps?, error?
│                   status: starting · streaming · suspended · reconnecting · failed · closed
├── telemetry       batteryPercentage?, charging, wifiEnabled?, bluetoothEnabled?,
│                   airplaneMode?, rotationLocked?, torchEnabled?, mobileDataEnabled?,
│                   locationEnabled?, volume{stream → current/maximum},
│                   linkLatency?, throughput?, framesPerSecond?
├── clipboard       kind (empty|text|image), text?, imagePng?, syncEnabled,
│                   availability (unknown|available|unavailable), message?
├── notifications[] id, packageName, title, body, timestamp
├── media           status, playback (unavailable|stopped|paused|playing),
│                   title?, artist?, artwork?, positionMs?, durationMs?
├── permissions     {capability → granted|denied|requiresSettings|unavailable}
├── recovery        phase (idle|detecting|reconnecting|restartingServices|recovered|failed),
│                   attempt, message?, error?
├── agentStatus     unavailable | starting | connected | reconnecting
├── wirelessDiscovery  status (idle|searching|ready|unavailable), advertisements[], message?
└── wirelessPairing    phase (idle|waitingForScan|pairing|findingConnection|
                        needsConnectionPort|connected|failed|expired),
                       qrPayload?, expiresAt?, host?, device?, error?
```

**Every nullable field means "the phone has not said".** That is a third state,
distinct from true and false, and the design must render it as such — never as
"off". A meter that invents a number is worse than an empty one.

**Note on the media scrubber:** the UI extrapolates a live position from the
last reported one while playback is playing, so the bar ticks without the phone
streaming a value every second.

**Note on `technicalDetails`:** every error can carry a diagnostic string. **The
UI must never display it.** It can contain a device serial, a network address or
a local path. It is copied deliberately, behind a "read it before sharing"
warning.

---

## 7. The seven states — every screen, every time

Non-negotiable. Design all seven for every surface:

**loading · empty · unavailable · permission-denied · error · recovery · success**

Plus these rules:

- **No screen is a dead end.** Each offers a next step or a retry. A phone list once became a dead end with no close button and every test stayed green.
- **Loading shows after a 150–300 ms delay and then stays ≥ 300 ms**, so fast paths do not flash. (Tokens in use: delay 200 ms, floor 400 ms.)
- **Skeletons mirror final content exactly.** No layout shift.
- **Empty screens invite an action**, they are not blanks.

---

## 8. Failure copy — the full catalogue

Twelve error codes exist. Every one must say **what happened and the next
move**. They never apologise and are never vague. This is the shipped copy; the
redesign must keep this level of specificity.

| Code | Guidance |
| --- | --- |
| `adbUnavailable` | "DroidPier could not run ADB. It ships with its own copy, so this usually means the file is missing or blocked." |
| `deviceUnauthorized` | "The phone has not allowed this computer yet. Unlock it and accept the debugging prompt." |
| `deviceOffline` | "ADB can see the phone but it is not answering. Unplug the cable and plug it back in." |
| `multipleDevices` | "More than one phone is connected, so DroidPier cannot tell which you mean." |
| `connectionFailed` | "The connection did not come up. If this is Wi-Fi, the phone must be on the same network." |
| `deploymentFailed` | "The companion could not be installed or started on the phone. Unlock the phone and allow the installation." |
| `permissionDenied` | "Android refused a permission DroidPier needs. Grant it on the phone." |
| `capabilityUnavailable` | "This build of Android does not offer {capability}. The rest of DroidPier works without it." |
| `protocolError` | "The desktop and the phone disagreed about the message they exchanged." |
| `timeout` | "The phone did not answer in time. A locked screen, a sleeping phone or a slow network will each do this." |
| `cancelled` | *(silent)* |
| `internal` | "Something failed inside DroidPier rather than on the phone. Copy the technical details." |

**Wireless failures get more specific advice again**, because a refused pairing
code and a phone that was never reached need opposite answers: `invalidInput` ·
`unreachable` · `rejected` · `authorization` · `discoveryUnavailable` ·
`unexpectedResponse` · `timeout` · `cancelled`.

Two examples of the register:

> "The phone refused the code. Android shows a fresh one every time that screen opens."

> "The phone did not answer at that address. It must be on the same network and the Wireless debugging screen must still be open."

---

## 9. Keyboard map

| Key | Action |
| --- | --- |
| `Ctrl + Space` | Toggle the launcher |
| `Ctrl + Shift + P` | Command palette |
| `Ctrl + /` · `F1` · `?` | Keyboard shortcuts |
| `Alt + Tab` | Switch window |
| `Alt + Shift + Tab` | Switch window backwards |
| `F11` | Toggle fullscreen |
| `Ctrl + Shift + D` | Stream diagnostics |
| `Ctrl + Shift + H` | Health readout |
| `Esc` | Close whatever is open, **one layer at a time** |

**The Escape ladder is ordered and one press peels exactly one layer:**
fullscreen → command palette → shortcut sheet → diagnostics → window switcher →
open desk surface → connection screen.

**Everything else belongs to the phone.** Unclaimed keystrokes are forwarded to
the focused Android window, modifiers included, so `Ctrl+C` reaches the phone as
a keycode with the right meta-state rather than as typed text. The shell must
never swallow keys indiscriminately — the drawer's own search box stops
accepting letters the moment it does.

---

## 10. Motion

| Token | Duration |
| --- | --- |
| micro | 120 ms |
| standard | 180 ms |
| enter | 260 ms |
| stagger between siblings | 55 ms, capped at 10 steps |

Curves: `easeOutCubic` for anything arriving; `easeInOut` for values that move
both ways.

**The vocabulary — four patterns, used everywhere, never hand-rolled:**

1. **Entrance** — staggered fade + short rise (10–18 px), so a screen *assembles* rather than snapping. Screens declare their own rhythm by ordering their elements.
2. **SwapText** — cross-fade + small slide for a value that changes, so readouts never jump.
3. **HoverLift** — desktop pointer response: brighten and lift by a hair (≈1.2%), never bounce. **Hover must out-contrast rest; selection must out-contrast hover.**
4. **Station pulse** — the Link Rail's active station breathes. This is the only sustained animation in the product.

**Rules:**

- **Animate `transform` and `opacity` only.** Never animate layout properties, never `transition: all`.
- Every animation is interruptible and honours reduced motion.
- **The stagger cap exists because a phone with 77 apps made the last icons arrive seconds after the first** — a staggered entrance became a slow load.
- **Motion earns its place on the Link Rail. Elsewhere, prefer stillness.** No perpetual decorative animation anywhere near the video stream.

---

## 11. Voice

- Name things by **what the user controls**, never by how the system is built: "Phone disconnected," not "socket closed."
- **Actions keep one name through a whole flow** — a button that says **Reconnect** produces a status that says **Reconnected**.
- **Sentence case everywhere.** Curly quotes. `…` not `...`. Non-breaking space between value and unit: `24 ms`, `1.2 MB/s`.
- Errors state what happened and the next move. They never apologise.
- **Only glyphs the bundled faces contain.** No `→` in user-visible strings.
- Never print internal identifiers. `voice_call` becomes "Voice call"; `music` becomes "Media".

---

## 12. Accessibility bar

- Fully keyboard operable, with a visible focus ring in the accent colour, never clipped.
- **Contrast judged perceptually (APCA-style), not by WCAG 2 ratio alone.** Hover, active and focus must each carry *more* contrast than rest.
- Hit targets: 24 minimum, 32 comfortable, 44 primary.
- Every interactive element has a semantic label. A grid of unlabelled colour swatches is unusable to anyone who cannot see them — each accent and wallpaper swatch is named.
- Reduced motion honoured throughout; the platform setting always wins.
- Light/dark parity is mandatory, both directions.

---

## 13. What is coming — design a home for these now

### 13.1 Desktop, high impact

| # | Feature | Design implication |
| --- | --- | --- |
| **W** | **Virtual desktops / workspaces** (2–4, `Ctrl+Alt+←/→`) | The single biggest "real desktop" gap. Needs a **taskbar workspace indicator**, a switcher affordance, and a "move window to workspace" entry in the title-bar menu. Design this into the taskbar now — retrofitting it later means redesigning the bar. |
| **Z** | **Per-window zoom / DPI scale** | Android apps render at phone density; a 4K monitor makes them unreadable. Needs a per-window scale control in the title bar or its menu. |
| **C** | **Screenshot and screen recording** — one window or the whole workspace, saved to a chosen folder, with a confirmation | Needs a capture affordance (tray or control centre), a target picker, a recording-in-progress indicator, and a completion toast with **Show in folder**. |
| **M** | **Multi-monitor awareness** — remember which display the shell opened on, per-display snapping | Affects snap previews and the settings surface. |
| **P** | **Picture-in-picture / always-on-top mini window** | A compact window chrome variant: no title text, minimal controls, higher elevation. |
| **T** | **Live window thumbnails in the Alt+Tab switcher**, MRU ordering | The switcher cards need a thumbnail slot designed in, with a graceful fallback to the app glyph. |
| **N** | **Notification actions** — inline reply, per-app mute, do-not-disturb | The notification row needs a reply affordance and a per-sender overflow menu; the centre header needs a DND toggle. |
| **D** | **Density setting** (compact / comfortable) | The token scale must support two spacing multipliers without redrawing components. |
| **B** | **Custom wallpaper** (user image, not only the shipped gradients) | Settings needs a file picker row and a preview. |
| **L** | **Localisation** — English only at first, but every string externalised | Layouts must tolerate ~35% text expansion. Avoid fixed-width labels. |
| **A** | **Desktop audio forwarding** | Currently the product's most requested absence. When it lands: a volume control that governs *the computer's* output, distinct from the phone volume sliders, plus an output-device row. |
| **F** | **Drag and drop between phone and desk** | Needs a drop-target treatment on the desk and on window bodies, and a transfer-progress indicator. |
| **K** | **Calendar flyout from the tray clock** | The clock is currently inert. |
| **Q** | **Quick settings not yet available** — brightness, resolution, keep-screen-on, wallpaper-on-phone | Extend the control centre grid. |

### 13.2 The Android companion app — the weakest surface in the product

The phone-side app is **four activities with no Compose dependency and a single
`styles.xml`**. One PNG is the entire visual identity. It is the first thing a
new user installs and the only DroidPier surface they see on the phone.
**It needs a full design, not a refresh.**

Current screens and strings:

- **Setup / status** — "Your Android. A bigger workspace." · "Not connected" / "Connecting…" / "Connected to DroidPier" / "Connection lost · reconnecting…" · **Connect from your computer** · **Disconnect desktop** · "Your connection stays local"
- **Permissions** — "Allow connection notifications" · "Phone notification access" · **Open notification access** · **Open developer settings** · **Open app info**
- **Project and help** — version, "Apache-2.0 · Independent open-source project"

Planned:

| # | Work |
| --- | --- |
| **C1** | **Jetpack Compose + Material 3** with dynamic colour |
| **C2** | **Stepped pairing flow** — Welcome → Permissions → Pair (QR or code) → Connected. Today the whole flow is one activity. |
| **C3** | **Live connection dashboard** — connected state, desktop name, session duration, bytes transferred, a large disconnect button. Users currently have no way to see the session from the phone. |
| **C4** | **Permission explainers** — one card per permission, what it is for, a direct settings intent. Permission denial is the top cause of a broken first run. |
| **C5** | **Ongoing notification redesign** — status plus a quick disconnect action. The foreground-service notification is the companion's persistent UI. |
| **C6** | **Brand pass** — adaptive launcher icon, monochrome icon for themed icons, splash screen, dark-theme parity. |
| **C7** | **Match the desktop language** — share the token values so both surfaces read as one product. |

**The companion design must be derived from the desktop tokens in §4**, adapted
to Material 3 and to a touch surface (where Android's 48 dp target rule *does*
apply), not designed independently.

### 13.3 Platform reach

Windows installer and portable ZIP; macOS Apple Silicon and Intel DMGs; Flatpak
and Snap; ARM builds. The design must not assume GTK window decorations or a
Linux-specific chrome.

---

## 14. Anti-patterns — read before generating

Every one of these has actually happened in this product or is an explicit
rejection of a default.

**Do not:**

- ❌ Put a **backdrop blur over live video**, or any always-on animation above it. This is the single most expensive mistake available here.
- ❌ Use **`signal` blue or `trace` emerald decoratively.** Blue means link state and primary action. Emerald means telemetry. Using either as ornament breaks the system.
- ❌ Ship a **warm/cream light mode.** Light stays in the same cool blue family or it reads as two products.
- ❌ Use **Inter**, or any system-font fallback. Body is Public Sans deliberately.
- ❌ Use **drop shadows for elevation.** A luminance step plus a hairline. (The single exception: glass panels over the wallpaper.)
- ❌ Use **pills or 0-radius brutalism** for cards and panels. The radius scale is 8 / 12 / 16.
- ❌ Draw a **centred title with a button underneath** as a screen. Compose: multi-column, panels, ambient light, readout strips.
- ❌ Draw a **fake phone screenshot** anywhere. The phone mirror renders hardware honestly and says the screen is unavailable.
- ❌ Show a **meter with an invented number.** A null value renders an empty track and `—`.
- ❌ Show a **control that cannot act.** Guidance text beats a button that lies.
- ❌ Use **`→` in any user-visible string.** The bundled faces lack it; it renders as a tofu box.
- ❌ Put a **raw frame rate in a window title.** It reads as a performance grade and gets reported as a bug.
- ❌ Use **transient toasts for persistent conditions.** A paused clipboard sync must still be visible ten minutes later.
- ❌ Colour a **not-yet-reported capability as a fault.** It is a state. Painting it red teaches people to ignore red.
- ❌ Build **eleven slightly different glasses.** One panel component, one blur radius, one edge treatment, used everywhere.
- ❌ Leave a **screen with no way out.**
- ❌ Add a **second carded clock** beside the large bare one. That is not composition.

---

## 15. Deliverables

Produce, in this order:

1. **A design system page** — every token in §4 rendered as swatches and specimens, in **both light and dark**, and in **both glass and matte modes**.
2. **A component library**: glass panel · matte panel · button (filled / outlined / ghost / icon) · switch · slider · segmented control · text field with search affordance · list row (rest / hover / selected / disabled) · card · context menu · tooltip · badge · status dot · meter · skeleton · banner (info / warn / fault / calm) · **window chrome** · **taskbar segment** · **Link Rail station and trace**.
3. **Every screen in §5**, at **1280×800** and **1920×1080**, in **light and dark**.
4. **Every state in §7** for each screen — not only the success path. The failure paths are where a beta is judged.
5. **The window state matrix from §5.6** — all eight window renderings.
6. **The taskbar at four widths** — 1920, 1280, 1000, 800 — showing what sheds where.
7. **Motion specifications** for the four patterns in §10, as timing/easing notes on the relevant screens.
8. **The Android companion flow** from §13.2 — four screens minimum, derived from the same tokens.
9. **A future-state view of the taskbar and title bar** showing where workspaces (§13.1 W), per-window zoom (Z) and capture (C) will live.

---

## Appendix — one-paragraph summary for a prompt box

> DroidPier is a Linux/Windows/macOS desktop application that brings a physical
> Android phone's apps into a real desktop workspace: an app launcher, freeform
> resizable app windows carrying live video from the phone, a segmented taskbar
> with a system tray, a control centre for the phone's radios and volumes, a
> notification centre, a clipboard bridge, and a USB/Wi-Fi connection manager
> with QR and manual ADB pairing. Its signature element is the **Link Rail**, an
> instrument that renders the real five-stage transport handshake — ADB, Device,
> Agent :3698, Companion :3699, Applications — as a rail with stations, which
> collapses to a live 4 px telemetry trace once connected. The visual language is
> **frosted glass over a lit blue-violet gradient wallpaper**: white at 5–15%,
> blur 24, one-pixel white edges, radii 8/12/16, deep navy `#0B1120` ground,
> blue `#60A5FA` reserved for link state and primary actions, emerald `#34D399`
> reserved for telemetry, Space Grotesk for display, Public Sans for body, IBM
> Plex Mono for every machine value. It must also render as **flat matte** with
> no blur whenever a window is streaming video. The audience is technical desktop
> users; density is high, motion is restrained, and every failure state says what
> happened and what to do next.
