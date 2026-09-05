# Changelog

## Unreleased

### The phone mirror is live

The *Phone Mirror* door used to open a frame that said a live screen was not
available. It now streams the phone's own display into that frame, view
only: scrcpy-server mirrors display 0 scaled to 540 px at 30 fps over a
single video socket, decoded through the same pipeline the app windows use.
The frame follows the phone when it rotates, letterboxing to the new
aspect, and says plainly what it is doing when it cannot show frames:
*Connecting…* while the stream comes up, the reason and a *Retry* when it
fails or stops, and a one-line explanation in builds that cannot mirror
(the preview harness is one). Opening the frame starts the stream; closing
it by any door stops it, and disconnecting the phone stops it with the
windows.

Deliberately not in this change:

- **Touch in the mirror.** The stream is opened with no control socket, so
  nothing on the desk can inject into the phone's own screen. That is the
  decision, not a gap: the mirror shows the phone, the windows drive it.
- **A decoder restart.** The windows restart a dead decoder once and ask the
  phone for a fresh key frame; without a control channel the mirror cannot
  ask, so a dead decoder ends the mirror with a retry offered instead of
  decoding garbage.
- **A blur over the live frame.** The phone frame goes flat while
  streaming, as it already did over a streaming window, because a blur
  above a texture re-blurs the desk on every one of its frames. The
  frame-cost test now pins this for the mirror too.

### Desktop UI brought to the reference design, surface by surface

Compared against the running reference implementation, page by page and
click by click, rather than against its source. What changed on screen:

- **Boot**: a *Select Device* button in the masthead, a 36 px headline, a
  line about what the product is once the link is up, the phone's name in
  bold on the transport card, a filled *Open Workspace* action, and a bench
  strip reading `PORT 3698: LISTEN · PORT 3699: SYNC · ADB: :5037`.
- **Desk**: the wallpaper bloom is a 650 px disc; the Link Rail's stations
  are 28 px discs with a status word; the search pill carries the Google
  wordmark; the dock is back · home · recents · search with dot-and-name
  chips and a round play/pause; the widget column is rebuilt to one card
  idiom (icon, label, chip, rule) with a scrubber, a battery gauge and doors
  to the control centre and the notification shade.
- **Launcher**: 672 wide with a header row (icon, borderless field, clear,
  ESC), a pinned section and a footer naming the phone.
- **Command palette**: icon wells, inline group chips, the reference's hint
  and ESC chip, shell → windows → apps order, and its footer.
- **Shortcut sheet**: one column of cards, a keyboard-icon header with the
  build, and an Escape Ladder card.
- **Window switcher**: `WINDOW SWITCHER (ALT + TAB)` / `Z-Order Stack`, 176 px
  cards with glyph, name, dot, a preview strip and the package, radius 24.
- **Window chrome**: rotate · fullscreen · minimise · maximise · close, one
  rotate glyph, and a *Live* badge that opens a STREAM PIPELINE card.
- **Diagnostics**: activity-icon header with subtitle, one three-column
  summary card, `ACTIVE VIDEO SURFACES (n)`, per-window rate strips, and a
  `RECENTLY CLOSED SESSIONS (LAST 8)` card.
- **Control centre**: `PHONE VOLUME LEVELS`, and *Manage Phones…* / *Desk
  Settings…* on one row with their glyphs.
- **Notification centre**: amber bell, *Notification Centre*, trash on
  *Clear all*, `n items` per sender, and the closing line about the phone
  being the source of truth.
- **Settings**: monitor-icon *Desk Settings* header, group icons and *Reset
  group*, accent cards with names, wallpaper chips (the default is now
  *Default Lit*; *Slate Precision*, *Forest Canopy*), a PHONE LINKS row of
  three tiles, and the audio caveat set as an amber caution.
- **Connection**: an eyebrow, *Look again* with its icon, device rows with an
  icon well and a USB / WI-FI badge, and segments *QR Code / Manual Entry /
  Nearby Hints* in that order.
- **Permissions**: shield header with subtitle, an *On* chip where nothing is
  left to manage, and the port-3699 footer.
- **Phone mirror**: the invented home screen is gone; the frame says what it
  will show once the phone casts.
- **Health HUD**: one solid line, bottom-left.
- **Recovery**: centred, with a 56 px phase ring above the headline.
- **First-run tour**: a progress rail, an icon well, a QUICK TOUR chip and
  the counter in the footer.
- **Token sheet**: Dark / Light and Glass / Matte toggles, underlined tabs,
  and every semantic role as a card showing both hexes.
- 91 more Lucide glyphs are bundled under `DexIcons`.
- **Window bodies**: a starting window shows the app's tile, name and
  package; a reconnecting one a 32 px ring above *Reconnecting to <app>*;
  a stopped one a rose tint, a 40 px alert mark and a *Close* beside *Try
  again*; a window with no video surface yet shows tile, name, package and a
  chip saying so — in the reference's composition, with this app's honest
  words.
- **Modal shells** are radius 20 under a 70 % scrim blurred at 12, as the
  reference draws every overlay; the window context menu is a 192 px slate
  card at radius 12; the tray clock reads `12:56 am` over `5 Sept`.
- **Diagnostics** closes with *Copy diagnostics report* and the close hint;
  **Connection** is headed `HARDWARE MANAGER` / *Manage Android Phones* over
  *Connected Devices*; the token sheet is the *DroidPier Token & Specimen
  Explorer*; the shortcut sheet carries *The Ordered Escape Ladder* and the
  reference's footer line.
- **Companion preview**: the phone-side app, rendered inside a phone frame
  as a review surface in the preview harness (`companion`), reading the
  mock snapshot for its link state, readouts, permissions and pairing. Not
  in the product, on purpose: a phone drawn on the desk is a picture of a
  phone.

- **On a real phone**: the Link chip always shows `RTT · TX · RATE`, with an
  em dash while the link is idle, instead of collapsing to `LINK |`; *Your
  Apps* is the reference's glass pill, not a filled key; the control centre's
  Wi-Fi and Bluetooth pills are slate with a coloured icon disc, the five
  toggles sit on one row at 44 px, and *Manage Phones…* is wired in the
  product; and the agent now draws adaptive app icons under the desk's
  rounded-square mask rather than the launcher's (a circle on some phones),
  so the desk shows tiles, not discs. Dark is the default theme — the design
  is the dark glass desk, and following the platform put a light desk in
  front of anyone on a light system.

- **From the reference's source, not its screenshots**: the clock's hands now
  *glide* — the second hand 100 ms linear, hour and minute 200 ms eased, the
  minute hand creeping with the seconds — instead of jumping, which is what
  the reference's CSS transitions do on every tick; the header carries the
  reference's four doors (*Tokens & Specs*, *Companion App*, *Phone
  Mirror*, *Boot Screen*), and the clock and widget column sit where it puts
  them; the control centre has 48 px toggles in the reference's colours,
  plain 4 px sliders with no tick marks, a *Shared Clipboard* card and the
  40×24 pill switch used everywhere now; the notification centre floats
  bottom-right above the tray with a card per sender, `2m ago` times and a
  dismiss that appears on hover; settings lose their boxed groups, gain
  equal-width accent and wallpaper grids, an About card with the build in
  signal and the audio caveat in amber, and modals run to 85 % of the
  screen so nothing is cut mid-row; the launcher key presses in while the
  launcher is up; window bodies say *Opening X…* and *Reconnecting to
  phone…* with the reference's second lines; the mirror and the token
  explorer carry its copy.
- **The companion view is in the product now**, behind the header's door,
  drawn on the companion's own Material 3 surfaces. Its big rose button is
  labelled *Close Companion View* rather than the reference's *Disconnect
  Desktop Session*, because that is what it does there too.

- **Third pass — behaviour on a real phone.** Everything that opens now
  *opens*: the launcher, every modal, the control centre, the notification
  centre, the mirror and the companion arrive with a short fade (the
  scrim) and a fade-and-scale (the card), on opacity and transform only,
  once; closing stays instant, and reduced motion skips it. The launcher
  no longer prints package names under user apps (system apps keep their
  small *System* tag). The tray's clock is a readout again — it opened the
  control centre, the same as the cluster beside it — and the cluster and
  bell wear a signal ring while their panel is open. Settings fill their
  672 card instead of a 620 column inside an 880 one. The companion view is
  its own phone frame on the scrim, fits short windows, and shows this
  computer's name and how long the link has been up. Every glyph sits on
  one scale (`DexIconSize`: 12 / 14 / 16 / 20 / 32 / 48) instead of the
  nine sizes that had crept in.

Not shipped, and why: the reference's Wi-Fi SSID subline (the facade does
not carry an SSID, and a placeholder would be a lie); its two-way Dark/Light
theme control (System is a real setting here); its `Skip tour` / `Step n of
4` wording (no capture of the tour exists to confirm it, and the tests pin
the current words).

Desktop shell improvements. Keyboard, launcher and window management.

- The theme selector is a real segmented control rather than Material chips.
  Material fills a selected chip from `secondaryContainer`, which resolved to
  emerald here — so choosing a theme lit up in the colour this design reserves
  for telemetry. A reserved role stops meaning anything the moment it is spent
  on selection.
- A phone that is ready reads emerald, and one waiting for you to tap "Allow"
  reads amber. Ready was blue, which is the colour of the Connect button beside
  it; waiting was red, though nothing had failed — a prompt is simply open on a
  screen you are not looking at.
- The recovery card opens on a ringed mark carrying the phase, and the shape
  changes with it rather than only the colour.
- "Needs phone settings" is amber rather than red. A capability waiting on a
  screen you have not opened yet is a state, not a failure, and painting states
  red is how people learn to ignore red. Granted is emerald, which is the
  colour this design reserves for reported facts.
- The window switcher shows each window's state as the same dot the dock draws,
  names the package under the label, and says which window releasing Alt will
  focus. Two windows of the same application were previously indistinguishable
  in it.
- The shortcut sheet says what happens to keys it does not claim: they go
  straight to the focused Android window.
- Removed eight golden images that no test referenced, two of them left over
  from a design direction this product no longer uses. A baseline nothing
  compares against is not a baseline; it is a picture of how things used to
  look, sitting in the folder where the record of how they do look is kept.
- Overlay cards go through the shared glass panel like everything else. The one
  surface that most needed the shared primitive was the one hand-rolling its
  own fill, hairline and blur — at 28 rather than the committed 24.
- The command palette leads with a search mark rather than a chevron, and says
  how to drive it. It is keyboard-first and the keys were not guessable from
  looking at it. It also gains a golden in both themes: nothing had ever looked
  at the surface every shell action is reached through.
- The website's three screenshots are regenerated from the current interface.
  They showed the desk, launcher and connection screen as they were before this
  rework.
- Shadows match the reference exactly. Every panel had been carrying one layer
  of black at 35% with no spread — three and a half times the ink, spreading
  wider than the panel it belonged to, which over a lit wallpaper reads as a
  smudge under every surface. Panels now use the reference's two layers at 10%,
  both pulled in by a negative spread. Windows keep a real shadow, at the
  reference's own values, because a window is the one thing on the desk that
  should cast one. The launcher button loses its blue halo for a plain
  elevation, and the rail's station glow stops blooming past the node.
- The desk clock follows the theme. Its face was a hardcoded near-black disc,
  so on the pale light desk it was the one thing that stayed dark.
- A design-token sheet, reachable from the command palette. Every semantic
  role, glass alpha, accent, wallpaper, type slot, radius, spacing step and
  duration, rendered from the tokens themselves rather than from a copy of
  them — so a value that drifts shows up beside the ones it should match. Glass
  and matte specimens sit side by side, because the only way to judge whether
  the matte fallback still reads as the same product is to see both at once.
- The first-run tour can happen. It was 214 lines with a test file covering
  every step, and it could never appear: the shell defaulted "already seen" to
  true, nothing passed it, and there was nowhere to remember it. Finishing it
  now sticks; an unreadable saved value shows it again rather than silently
  never showing it.
- The phone mirror has a door. Docked bottom-right above the taskbar, where its
  own documentation always said it belonged and where nothing ever put it, and
  reachable from the command palette. It goes flat whenever a window is
  streaming.
- Removed a carded clock widget that nothing built, and two card sizes nothing
  asked for. The test that guarded against a second clock now counts the clocks
  on the desk instead of asserting that one particular unused widget is absent.
- One icon set, drawn at one weight. The interface had been picking between
  Material's filled, outlined and rounded variants per call site, so a filled
  battery sat beside an outlined settings gear in the same tray. Icons now come
  from a single bundled Lucide face through one vocabulary that names what a
  glyph means rather than what it looks like, so the mismatch cannot recur.
  Against hairline edges, mono readouts and 1px rules, an outline set reads as
  instrumentation rather than as a phone launcher.
- Virtual desktops. The dock carries four numbered keys; choosing one changes
  which windows are on screen, and a window opened on desk 3 stays on desk 3.
  Switching is a change of view, not of state — a window on another desk keeps
  its size, position and stream, and comes back exactly as it was. The keys
  shed on a narrow bar, where reaching the launcher matters more.
- The launcher button says "Your apps" instead of being a coloured square with
  a glyph in it. It is the one control that opens everything, and an unlabelled
  icon asks a first-time user to guess at the moment they have least to go on.
- Fixed: the taskbar's width budget let two clusters claim more room than the
  bar had. It survived while the dock held less; the additions above overflowed
  it by 49 px at 1280 with windows open. There is now one budget — measure what
  cannot shrink, split what is left — so the bar cannot overflow at any width.
  A comment claiming the tray shed controls one by one has been corrected: it
  scrolls, from the bell end, so the clock stays put.
- The launcher is the size of what it holds. It was a fixed full-height card,
  so three apps sat in the corner of roughly 850 px of empty glass. Search
  results had been pushed down to hug the field to stop a gap opening between
  the query and its results, which moved the void to the top rather than
  removing it. The card now hugs its content, sits near the top of the screen,
  and heads with the search field — so results read downward from what you
  typed, and a phone's worth of apps still fits and scrolls.
- The Link Rail's connected state is on the desk. The rail is the one object
  this product asks you to learn, and it has three states: the full rail during
  boot, the recovery rail, and the collapsed live trace. The third — the state a
  connected user looks at all day — was built and then wired only into the
  preview harness, so the desk never showed it. It now sits in the top-left
  corner carrying `RTT`, `TX` and `RATE` from live telemetry, sheds readouts as
  the window narrows rather than overflowing, and is the one piece of desk
  furniture that does *not* fade behind a streaming window: whether the link is
  healthy is exactly what you want to read while something is streaming.
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
