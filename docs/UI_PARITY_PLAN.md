# UI parity plan — the reference implementation, surface by surface

The reference is the React implementation of `UI_REDESIGN_BRIEF.md` that was
handed over as `droidpier-desktop.zip`. Everything below was found by **running
it** (`npm run dev`, 1440×900, dark) and screenshotting every page and the key
interactions, then comparing against this application's goldens. Reading the
source alone missed most of this. The captures live in `.tools/reference-shots/`
(local, not committed); `x-*.png` are interaction states.

Each item is something visible. Tick it when the golden shows it.

## 1. Cross-cutting

- [x] **Wallpaper bloom is a circle.** The reference paints a 650×650 disc pinned
      top-right, `radial-gradient(circle at 100% 0%, white 15% → transparent 70%)`,
      with a soft but *visible* edge. Ours is a diffuse gradient with no edge.
- [ ] **Hover motion.** Desk icon tiles scale to 1.05 on hover; the launcher
      button scales to 1.02 and brightens its border; every chip brightens its
      fill (`white/10 → white/20`). All transitions 150 ms. Ours lifts 1 % and
      changes fill only.
- [ ] **Modal shells are radius 20**, not 16, everywhere the reference uses a
      card over a scrim (drawer, palette, sheet, settings, connect, permissions,
      diagnostics, companion). The switcher, recovery and tour cards are 24.
- [ ] **Scrims.** Modals: `slate-950/70` + blur 12. Drawer: `slate-950/60` +
      blur 24. Tour: blur 8. Recovery: `#0B1120/92` + blur 24.
- [x] **Rotate icon** is `rotateCw`, not a phone glyph; window control order is
      rotate · fullscreen · minimise · maximise · close.
- [ ] **Accent propagation.** With Phosphor selected the clock's second hand,
      the selected workspace key, the launcher button, toggles and the
      selected-row fills all go amber. Verify every `signal` use is `withAccent`.

## 2. Desk

- [x] **Search pill**: the multicolour *Google* wordmark drawn as letters
      (`G` `#4285F4`, `o` `#EA4335`, `o` `#FBBC05`, `g` `#4285F4`, `l` `#34D399`,
      `e` `#EA4335`, bold, tight tracking), placeholder "Search the web or
      apps…", a **search** icon on the right (ours has a mic), `rounded-full`,
      `max-w-sm`.
- [ ] **Desk icons**: four, not six. 48 px `rounded-[14px]` tile, label 11 px
      white with a drop shadow, wrapper `p-2 rounded-[14px] hover:bg-white/10`,
      tile `scale-105` on hover.
- [x] **Widget column** is 310 wide at `right: 40`, cards `p-4 rounded-[16px]`
      with `gap-3.5`, each header a mono uppercase label + icon on the left and a
      chip on the right, over a `border-b white/10` rule.
- [x] **Now Playing**: right chip `PHONE AUDIO`; 48 px `rounded-[8px]` artwork;
      4 px scrubber `white/10` filled in the accent; mono times `1:24 / 5:16`;
      centred transport with a **round** play/pause (`bg-white/20`).
- [x] **Desk Mode**: right label `PIXEL 8 PRO · ANDROID 15` (model · version,
      mono 10); battery row with a charging icon, `84% (Fast charging)` in mono
      and a 6 px gauge; a **2-column grid of radio tiles** (`p-2.5 rounded-[10px]
      bg-white/4`): Wi-Fi icon + "Wi-Fi 5GHz" + SSID, link icon + "Link
      Transport" + "USB High-Speed"; then a right-aligned "Open quick settings"
      affordance in mono that turns signal on hover.
- [x] **Notifications**: right chip `4 new` in amber; three compact rows
      (sender · mono time · body); affordance "View notification shade" that
      turns amber on hover.

## 3. Taskbar

- [x] **Nav pill order and glyphs**: `‹` back · `○` home · `□` recents · search.
      Ours opens with a hamburger and has no recents key.
- [x] **Running-app chips** are dot + name only, no icon.
- [x] **Media pill** is a round play/pause (`bg-white/15`) plus the title at
      11 px — not glyph + title + artist + three transport buttons.
- [ ] **Tray clock** reads `12:56 am` over `5 Sept` (lowercase meridiem, day +
      short month).
- [ ] **Hover** on chips brightens; the launcher scales 1.02.

## 4. Window chrome and body states

- [x] **Live tooltip** is a card, not a system tooltip: `w-48 rounded-[10px]
      bg-slate-900/95 border-white/20`, heading `STREAM PIPELINE` in mono, then
      Produced / Presented (emerald) / Dropped rows.
- [ ] **Context menu**: `w-48 rounded-[12px] bg-slate-900/95`, rows "Snap left
      half ⊞ Left", "Snap right half", rotate, maximise/restore, "Close window"
      in rose.
- [ ] **Starting**: whole body pulses; a `rounded-[14px]` accent-tinted tile with
      a spinning refresh icon; "Opening X…"; mono "Allocating hardware video
      surface on device".
- [ ] **Reconnecting**: a bare 32 px spinning signal ring; "Reconnecting to
      phone…"; mono "Re-establishing socket pipe on :3698".
- [ ] **Failed**: `bg-rose/5 border-rose/30`, 40 px alert icon, "This app
      stopped", **Try Again** + **Copy Technical Details**.
- [ ] **Placeholder surface** (no video yet): a 64 px accent tile, the package
      in mono, and a chip "Hardware video surface streaming at N fps".

## 5. Boot

- [x] **Masthead**: a **Select Device** button on the right (phone icon,
      `bg-white/10 rounded-[10px]`); the build string carries a `v`.
- [x] **Headline** is 36 px / 700 display, not 32 / 600.
- [x] A static body paragraph under the headline when ready: "Bringing
      applications on your physical phone into a freeform desktop workspace.
      The apps run on the phone; your computer provides the desk."
- [x] **Target Transport Node** card: the device name **bold on its own line**
      beside the emerald phone icon, then a mono line `Android 15
      (VanillaIceCream) · USB Link`.
- [x] **Primary action** is a filled signal button "Open Workspace" with an
      arrow icon, `px-6 py-3 rounded-[12px] font-bold`, ambient
      `shadow-lg shadow-signal/20`.
- [x] **Rail stations are 28 px discs**, not 8 px dots: complete = filled signal
      with a white check and a `0 0 12px signal/40` glow; active = signal ring
      over `signal/20` with a spinner; failed = filled rose with an alert mark;
      pending = slate ring with an 8 px dot. Connector is **2 px** in
      signal / rose / slate-700. Each station carries its **status word**
      (`COMPLETE`) in uppercase mono on the right and its detail line in mono
      below the label.
- [x] Rail card title is **"Five-Stage Hardware Handshake"** (title case).
- [x] **Bench strip** reads `PORT 3698: LISTEN   PORT 3699: SYNC   ADB: :5037`
      on the left and `● Local Privacy Verified · Zero Cloud Relay` on the right.

## 6. Launcher

- [ ] Card is **672 wide**, `max-h 80vh`, radius 20, anchored **64 px** from the
      top. Ours is 880 wide at 48.
- [x] **Header row**, not a boxed field: 20 px search icon, a **borderless**
      input with placeholder "Search phone apps (e.g. 'wa' for WhatsApp, or app
      name)…", an X to clear once typing, and an `ESC to close` mono chip; the
      row has `p-4` and a `border-b white/10`.
- [x] **Pinned to Top** section carries a pin icon in signal and is hidden while
      searching. Pinned rows show the *category* as their subline.
- [ ] Rows: `p-2.5 rounded-[12px] bg-white/4 border-white/5`, hover
      `bg-white/14 border-white/20`; a pin/unpin button appears on hover; the
      keyboard-selected row is `bg-white/25 border-white/40 ring-1`.
- [ ] Body has `p-4` and `space-y-5` between sections.
- [x] **Footer** `p-3 border-t`: "↑/↓ to navigate · Enter to launch" left,
      "Live device apps (Pixel 8 Pro)" right in mono — the *device name*.

## 7. Command palette

- [ ] Card **576 wide**, `max-h 75vh`, radius 20, anchored **80 px** from top.
- [x] Header: signal search icon, input "Type a command or search actions
      (Ctrl+Shift+P)…", `ESC` chip.
- [x] Rows carry a **32 px `rounded-[8px] bg-white/10` icon well** and the
      **group as an inline chip** after the title (`SHELL` / `DEVICE` /
      `WINDOWS` / `APPS`, 9 px mono), with a description line under it — not
      section headers.
- [x] Order: shell, device, windows, apps.
- [x] Footer: "Navigation: ↑ / ↓ to choose · Enter to execute" | "Unified Shell
      Dispatcher".

## 8. Shortcut sheet

- [x] Header: keyboard icon in a signal well, "Keyboard Shortcuts", mono
      subtitle "Desktop Accelerator Map · Build vX", X.
- [ ] Groups `LAUNCHER & DESK` / `WINDOW MANAGEMENT` / `HARDWARE & DIAGNOSTICS`,
      **single column**, each row a `p-2 rounded-[10px] bg-white/3` card with the
      kbd chip on the right. Keep the registry as the source.
- [ ] An **Escape Ladder card**: "The Ordered Escape Ladder", "Pressing [Esc]
      closes whatever is open, exactly one layer at a time:", then the chain in
      signal mono.
- [ ] Footer: "All unclaimed keystrokes pass directly through to the active
      Android window".

## 9. Window switcher

- [x] Card `max-w-2xl p-6 rounded-[24px] border-white/25`; header
      `WINDOW SWITCHER (ALT + TAB)` left and `Z-Order Stack (n active)` right in
      mono over a rule.
- [x] Cards are `h-36 p-3.5 rounded-[16px]` in three columns: **20 px accent chip
      + label top-left, status dot top-right**, a centred `rounded-[8px]
      bg-black/40` mono preview slot ("44 fps live stream" / "Minimised to
      Dock"), package in mono at the bottom.
- [ ] Selected: `bg-white/25 border-white/50 ring-2 ring-signal scale-1.02`.

## 10. Diagnostics

- [x] Header: activity icon in an emerald well, "Stream Diagnostics", subtitle
      "Deliberately not a debug dump. Every row is something you can act on.", X.
- [x] **One** summary card with three columns (`p-3.5 rounded-[14px]
      bg-white/4`): labels 10 px uppercase, values `text-base font-bold` mono,
      sublines `Optimal (< 20ms)` in emerald / `USB 3.1 High-speed` /
      `Tested 39–47 range`.
- [x] `ACTIVE VIDEO SURFACES (n)`; per-window card with label + package (mono,
      right) and an inner **black/40 three-column strip** PRODUCED / PRESENTED
      (emerald) / DROPPED.
- [x] `RECENTLY CLOSED SESSIONS (LAST 8)` card with a clock icon and bullet
      lines.
- [ ] Footer: "Copy diagnostics report" (copy icon, `bg-white/10`) left; "Press
      Ctrl+Shift+D to close" right.

## 11. Control centre

- [ ] Wi-Fi pill subline is the **SSID**; both wide pills have a **round icon
      well** (emerald when on, signal for Bluetooth).
- [x] Volume header reads `PHONE VOLUME LEVELS`.
- [x] Footer links **"Manage Phones…"** (phone icon) and **"Desk Settings…"**
      (sliders icon) — wire the two callbacks that exist and are never passed.

## 12. Notification centre

- [x] Header: **amber bell icon**, "Notification Centre", count chip, "Clear all"
      with a **trash icon**.
- [x] Group header strip: sender bold + `n items` in mono.
- [x] Footer text exactly: "The physical phone remains the authoritative source
      of truth".

## 13. Settings

- [x] Header: monitor icon + **"Desk Settings"** + X; each group label carries
      its icon (palette / monitor / phone) and a "Reset group" with a rotate-ccw
      icon.
- [x] **Accent** as six bordered swatch **cards** (20 px circle + name; selected
      has a check and `bg-white/10`).
- [x] **Wallpaper** as a 4-column grid of `colour chip + name` cards, selected
      ringed — not gradient thumbnails with names beneath.
- [x] **PHONE LINKS**: a row of three tiles — "Manage Phones… / Switch phone or
      pair Wi-Fi", "Permissions… / What phone has granted desk", "Disconnect /
      End active session" in rose.
- [x] About: an **amber caution box** for the audio-forwarding limitation.
- [ ] Theme is a **two**-way Dark / Light segmented; ours keeps System, which the
      reference lacks — keep ours, style to match.

## 14. Connection

- [ ] Eyebrow `HARDWARE MANAGER` in signal mono; title **"Manage Android
      Phones"**; X.
- [ ] Left header "Connected Devices" + "Look again" with a refresh icon
      (`bg-white/10`).
- [ ] Device cards: 40 px `rounded-[10px] bg-white/10` phone icon well; name;
      mono `model · version`; a **transport badge** top-right (`USB` signal/20,
      `WIFI` emerald/20); a rule; a status row with an icon (check-circle
      emerald "Ready" / alert-circle amber "Tap "Allow" on the phone") and the
      button (**Connect** filled signal / **Active Link** grey).
- [ ] Selected card `ring-1 ring-signal bg-white/20`.
- [x] Right: segmented **QR Code / Manual Entry / Nearby Hints** in that order;
      the QR card is white `rounded-[16px]` with the code framed in
      `border-4 slate-900`, "Scan from Developer options", instructions, "Code
      expires in 118s" in amber with an underlined "New code".

## 15. Permissions

- [ ] Header: **shield-check in emerald** + "What the desk can use" + subtitle +
      X.
- [ ] Rows carry a **40 px icon well** (bell / music / copy / phone-call /
      volume).
- [x] Controls: **"On"** as an emerald/20 chip with a check-circle; "Turn on"
      `bg-white/10`; "Open on phone" amber with an external-link mark; "Not on
      this phone" italic mono.
- [x] Footer: "Permissions are verified live with companion service on port
      3699".

## 16. Phone mirror

- [ ] 240×480, `rounded-[36px] bg-#0F172A border-6 slate-700 shadow-2xl`; a
      `h-7 bg-black/70` status bar with `12:00`, a punch-hole and wifi/battery;
      a slate gradient screen; an X; a 40 px circular phone badge; the device
      name; mono "Physical device surface linked via ADB. Screen mirroring
      handled in freeform windows."; an 80×4 gesture pill.
- [x] **Ours draws an app grid inside the phone.** That is a fake phone screen,
      which §14 forbids and the reference does not do. Replace with the honest
      placeholder above.

## 17. Health HUD

- [x] **Bottom-left** (`left: 16, bottom: 64`), not bottom-right.
- [x] One line: `● 42 fps  RTT: 14ms  TX: 4.8MB/s  Target: WhatsApp` in mono 11,
      solid `#0B1120` with a slate-700 border, radius 8, no blur, no pointer.

## 18. Token sheet

- [ ] Header: palette icon well, "DroidPier Token & Specimen Explorer", mono
      subtitle, **Dark / Light** and **Glass / Matte** segmented controls, X.
- [x] Tabs are **underlined** in signal, not a segmented pill.
- [x] Semantic roles as **cards** showing **both** hexes (`#0B1120 / #EEF2FB`)
      and the purpose; accent cards with circle + name + hex; wallpaper cards
      with the gradient + name.

## 19. Recovery overlay (from source — never triggered in the demo)

- [x] Card centred, `max-w-md p-8 rounded-[24px]`, text centred; a **56 px ring
      above the headline** (not 40 px beside it); headline `text-xl` bold
      display; mono sub-line; Reconnect Now / Disconnect only for
      reconnecting / failed.

## 20. First-run tour (from source — never opened in the demo)

- [x] Card `max-w-md p-6 rounded-[24px]`; a **progress rail** of four bars
      (active `w-6` signal, rest `w-2 white/20`) with "Skip tour"; a 48 px
      `rounded-[14px] signal/20` icon well; title with a **mono badge chip**
      (`Ctrl + Space`, `Edge Snapping`, `Alt + Tab`, `Tray Control Centre`);
      description; footer "Step 1 of 4" + Next / "Done — Open Workspace".

## 21. Android companion view

- [ ] Not in the product. A phone frame `max-w-sm h-640 rounded-[36px]
      bg-#1C1B1F border-8 slate-800` on **Material 3 tokens**: status bar, app
      bar (avatar `D`, "DroidPier Companion" / "Jetpack Compose M3 UI"), tabs
      Dashboard / Permissions / Pairing, a "Connected to Desktop" card with
      DURATION and DATA TX, a FOREGROUND NOTIFICATION card, a full-width rose
      "Disconnect Desktop Session", a gesture bar.
- [ ] **Where it lives**: the preview harness, as a review surface. Shipping an
      imitation of another app's screens inside the desktop is exactly the fake
      phone screenshot §14 forbids; a review surface is where the reference
      itself keeps it (a demo button, not product chrome).

## Not copied, on purpose

- The reference's **light mode** hardcodes `text-white` in every component and
  is unreadable; ours is the working one.
- The reference's **entrance animations** are referenced 30 times and defined
  nowhere; ours exist.
- `→` in user-visible strings: the bundled faces have no glyph for it. Use a
  chevron icon where the reference writes an arrow.
