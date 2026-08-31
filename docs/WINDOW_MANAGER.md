# Window manager — behaviour specification

This document records design behaviour, including planned work. It is not a
compatibility or feature acceptance report; see [compatibility](COMPATIBILITY.md).

M8 replaces external scrcpy windows with app windows composited **inside** the
DroidPier workspace. This is the behaviour the UI implements. Written
before the widgets, because the hard parts here are ownership and state, not
painting.

## Gap matrix — what the current shell has, and what M8 needs

| Behaviour | Today | M8 needs | Gap |
| --- | --- | --- | --- |
| App windows | External, owned by scrcpy | Composited in the workspace | **All of it** |
| Dock/taskbar entries | Focus and close only | Focus, raise, minimise, restore, close | Extend |
| Focus | `isFocused` flag, no visual window | A focused frame that takes keyboard | New |
| Z-order | None | Explicit, independent of focus | New |
| Geometry | None | Move, resize, snap, maximise | New |
| Minimise/restore | None | Round-trip via dock | New |
| Input routing | scrcpy's own window handled it | Pointer and keys reach the focused app | New, contract-dependent |
| Empty workspace | "Open an app" desk | Same desk, unchanged | None |
| Disconnected / recovery | Overlay covers everything | Windows must survive and restore | Extend |

## Freeform windows, not tabs

M8 requires two apps *simultaneously visible*, movable, resizable and
independently minimisable. Tabs give one visible surface at a time, so they
cannot satisfy it. Freeform it is — the cost is that we must implement drag,
resize, snapping and z-order ourselves, which the rest of this document is.

## State ownership

The backend owns geometry, z-order, display state and focus. The UI **sends
intent and renders what comes back**; it never stores a window's position.

This matters most during a drag. The tempting design keeps a local offset and
reconciles later, which means the window is briefly showing something the
backend has not agreed to — and if the backend rejects or clamps the move, the
window jumps. Instead the UI streams intent during the gesture and renders only
returned state. If that proves visibly laggy on real hardware, the fix is a
backend that answers faster or an explicit interpolation contract, not a second
source of truth in the UI.

## Behaviour

**Focus.** Clicking anywhere in a window focuses it and raises it. Focus is
distinct from z-order — a window can be raised without focus (via the dock) and
focused without moving in z (it is already on top). The focused window takes a
`signal`-coloured frame; unfocused windows keep a hairline border.

**Drag.** By the title bar only. The body belongs to the Android app and its
input. Dragging past the workspace edge clamps rather than allowing a window to
be lost; the title bar always stays reachable.

**Resize.** Eight handles, 8 px hit slop outside the frame so a 1 px border is
still grabbable. Minimum 240×180 — below that an Android app is unusable and
the frame chrome dominates.

**Snap.** Drag to an edge to half-screen, to a corner for a quarter, to the top
to maximise. Preview overlay before release, so a snap is never a surprise.

**Minimise.** The window leaves the workspace and stays in the dock with a
dimmed running-dot. Restoring returns it to its previous geometry, which the
backend must remember — the UI deliberately does not.

**Maximise.** Fills the workspace minus the menu bar and dock. Restore returns
the pre-maximise geometry. Double-clicking the title bar toggles.

**Close.** Ends the session. The dock entry disappears. No confirmation: the
Android app keeps running on the phone, so nothing is destroyed.

**Keyboard.** Keys reach the focused window's Android app. The shell keeps only
Ctrl+Space (launcher) and Escape (dismiss overlay) — every other combination
belongs to the app, or Android apps become unusable. Alt+Tab cycles focus and
raises; the launcher and control centre remain reachable while a window has
focus.

## States every window frame must render

Not just the streaming one. Each has been a source of dishonest UI elsewhere in
this codebase, so each is specified:

| State | Frame shows |
| --- | --- |
| `starting` | Skeleton at the app's own colour, label "Opening…" |
| `streaming` | The surface |
| `suspended` | Last frame dimmed, "Paused" — never a blank box |
| `reconnecting` | Last frame dimmed with the rail's travelling trace |
| `failed` | Fault-bordered frame, the error's message, and a Retry |
| `closed` | Removed from the workspace entirely |

A window whose surface is null but whose status is `streaming` renders the
skeleton, not an empty rectangle. That combination means the backend has not
handed us pixels yet, and an empty rectangle would read as a broken app.

## Test obligations

M8 names these; they are the acceptance bar, not a suggestion:

- two overlapping windows, both visible
- focus transfer between them, with z-order following
- minimise then restore, geometry preserved
- maximise then restore
- close
- launching from the app drawer into the workspace
- keyboard traversal reaching the focused window

Every golden image is opened and looked at before it is accepted. A green suite
has already hidden a blank screen once in this project.
