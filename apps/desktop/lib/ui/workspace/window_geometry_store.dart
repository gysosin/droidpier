import 'package:flutter/widgets.dart';
import 'package:open_dex_api/open_dex_api.dart';

import 'window_model.dart';

/// The most placements kept. Matches the bootstrap's own cap.
///
/// Bounded because a long-lived install would otherwise grow the settings file
/// forever, one entry per application ever opened.
const int maxRememberedWindows = 64;

/// Where one application's window was last left.
@immutable
class RememberedWindow {
  const RememberedWindow({required this.geometry, required this.maximised});

  final WindowGeometry geometry;

  /// Travels with the rectangle: relaunching a maximised app and silently
  /// losing that is a regression a person notices at once.
  final bool maximised;
}

/// Records [geometry] for [packageName], evicting the least recently placed
/// entry once [maxRememberedWindows] is exceeded.
///
/// Returns a new map; the caller owns persistence. Re-remembering a package
/// moves it to the end, so an app you keep using is never the one evicted.
Map<String, RememberedWindow> rememberWindow(
  Map<String, RememberedWindow> current,
  String packageName,
  WindowGeometry geometry, {
  required bool maximised,
}) {
  final Map<String, RememberedWindow> next = Map<String, RememberedWindow>.of(
    current,
  )..remove(packageName);

  next[packageName] = RememberedWindow(
    geometry: geometry,
    maximised: maximised,
  );

  // Dart preserves insertion order, so the first key is the oldest.
  while (next.length > maxRememberedWindows) {
    next.remove(next.keys.first);
  }
  return next;
}

/// The remembered placement for [packageName], clamped into [workspace].
///
/// Null when nothing was recorded, which is the caller's cue to fall back to
/// cascade placement.
///
/// Clamping is not optional: a rectangle saved on a large monitor would
/// otherwise restore beyond the edge of a smaller one, and the title bar is the
/// only way to drag a window back.
WindowGeometry? recallWindow(
  Map<String, RememberedWindow> store,
  String packageName,
  Size workspace,
) {
  final RememberedWindow? remembered = store[packageName];
  if (remembered == null) return null;
  return remembered.geometry.clampedTo(workspace);
}
