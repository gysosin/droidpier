import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// How input reaches the Android app inside a window.
///
/// Whether the backend wants raw pointer and key events from the UI, or the
/// embedded surface consumes them itself once focused, is still open — see
/// `docs/ARCHITECTURE.md` for the facade boundary. Rather than guess and build
/// a frame that has to be taken apart later, the frame delegates to one of
/// these and the answer swaps a single line.
///
/// Neither implementation is a placeholder: both are what the real thing would
/// be under their respective answers.
abstract interface class WindowInput {
  /// Wraps the window body. [enabled] is false for an unfocused window, which
  /// must not receive input meant for the focused one.
  Widget wrap({required Widget child, required bool enabled});
}

/// The surface consumes input itself.
///
/// The UI hands pointers straight through and does nothing — correct if the
/// embedded texture is backed by a platform view that already routes input.
class SurfaceConsumesInput implements WindowInput {
  const SurfaceConsumesInput();

  @override
  Widget wrap({required Widget child, required bool enabled}) {
    // An unfocused window still must not swallow clicks meant to focus it, so
    // absorbing is deliberately not used here: the frame's own Listener needs
    // to see the pointer-down.
    return enabled ? child : ExcludeSemantics(child: child);
  }
}

/// The UI forwards raw events to the backend.
///
/// Correct if the backend exposes something like `sendPointerEvent(sessionId,
/// …)`. Positions are reported in **surface pixels**, not widget logical
/// pixels: the window is scaled to fit its frame, so a tap at the centre of a
/// 400 px-wide frame is not a tap at x=200 on a 1080 px-wide phone.
class ForwardInputToBackend implements WindowInput {
  const ForwardInputToBackend({
    required this.surfacePixelSize,
    required this.onPointer,
    this.onKey,
  });

  final Size surfacePixelSize;
  final void Function(PointerEvent event, Offset surfacePosition) onPointer;
  final void Function(KeyEvent event)? onKey;

  Offset _toSurface(Offset local, Size widgetSize) {
    if (widgetSize.isEmpty) {
      return Offset.zero;
    }
    return Offset(
      local.dx * surfacePixelSize.width / widgetSize.width,
      local.dy * surfacePixelSize.height / widgetSize.height,
    );
  }

  @override
  Widget wrap({required Widget child, required bool enabled}) {
    if (!enabled) {
      return child;
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        return Listener(
          onPointerDown: (PointerDownEvent e) =>
              onPointer(e, _toSurface(e.localPosition, size)),
          onPointerMove: (PointerMoveEvent e) =>
              onPointer(e, _toSurface(e.localPosition, size)),
          onPointerUp: (PointerUpEvent e) =>
              onPointer(e, _toSurface(e.localPosition, size)),
          onPointerSignal: (PointerSignalEvent e) =>
              onPointer(e, _toSurface(e.localPosition, size)),
          child: child,
        );
      },
    );
  }
}

/// Converts a Flutter pointer event into the backend's wire sample.
///
/// Kept out of the widget so it can be tested directly: getting the phase or
/// the coordinate space wrong puts every touch in the wrong place on the
/// phone, and that is not something a widget test would catch by eye.
WindowPointerSample? windowPointerSample(
  PointerEvent event,
  Offset surfacePosition,
) {
  final WindowPointerPhase? phase = switch (event) {
    PointerDownEvent() => WindowPointerPhase.down,
    PointerMoveEvent() => WindowPointerPhase.move,
    PointerUpEvent() => WindowPointerPhase.up,
    PointerCancelEvent() => WindowPointerPhase.cancel,
    PointerScrollEvent() => WindowPointerPhase.scroll,
    // Hover and every other event the backend has no phase for is dropped
    // rather than guessed at.
    _ => null,
  };
  if (phase == null) return null;

  final Offset scroll = event is PointerScrollEvent
      ? event.scrollDelta
      : Offset.zero;

  return WindowPointerSample(
    phase: phase,
    x: surfacePosition.dx,
    y: surfacePosition.dy,
    pointerId: event.pointer,
    buttons: event.buttons,
    scrollDeltaX: scroll.dx,
    scrollDeltaY: scroll.dy,
  );
}

/// Converts a Flutter key event into the backend's wire sample.
///
/// Returns null for anything that is not a plain down or up — a repeat is a
/// down with [WindowKeySample.repeat] set, and Flutter's synthesised events
/// have no meaning on the far side.
WindowKeySample? windowKeySample(KeyEvent event) {
  final WindowKeyPhase? phase = switch (event) {
    KeyDownEvent() || KeyRepeatEvent() => WindowKeyPhase.down,
    KeyUpEvent() => WindowKeyPhase.up,
    // Any future event type is dropped rather than guessed at.
    _ => null,
  };
  if (phase == null) return null;
  final HardwareKeyboard keyboard = HardwareKeyboard.instance;
  return WindowKeySample(
    phase: phase,
    physicalKeyId: event.physicalKey.usbHidUsage,
    logicalKeyId: event.logicalKey.keyId,
    character: event.character,
    repeat: event is KeyRepeatEvent,
    // Snapshot the modifiers so command combinations survive the trip: a Ctrl+C
    // must arrive as a keycode with Ctrl set, not as the character 'c'.
    ctrl: keyboard.isControlPressed,
    shift: keyboard.isShiftPressed,
    alt: keyboard.isAltPressed,
    meta: keyboard.isMetaPressed,
  );
}
