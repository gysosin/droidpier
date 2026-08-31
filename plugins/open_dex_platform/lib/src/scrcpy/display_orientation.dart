import 'package:open_dex_api/open_dex_api.dart';

/// Chooses the display size to request for a fresh Android window so its content
/// starts the right way up.
///
/// scrcpy's `new_display=WxH` fixes the virtual display's orientation. A phone
/// whose launcher is portrait-locked — nearly all of them — renders rotated 90°
/// inside a landscape display, because Android composites the portrait content
/// sideways to fill it. So the display must be created in the phone's own
/// orientation. Whatever the app does *after* launch — a video going fullscreen
/// landscape, say — arrives as a fresh session header and the gateway follows
/// it; this only has to get the *starting* orientation right.
class DisplayOrientation {
  const DisplayOrientation._();

  /// Portrait when the phone's natural display is at least as tall as it is
  /// wide, landscape otherwise; [fallback] when the output cannot be read.
  ///
  /// Reads the `Physical size:` line of `adb shell wm size` in preference to an
  /// `Override size:` a previous session may have left, since orientation should
  /// follow the panel, not a leftover override.
  static WindowPixelSize fromWmSize(
    String wmSizeOutput, {
    required WindowPixelSize portrait,
    required WindowPixelSize landscape,
    required WindowPixelSize fallback,
  }) {
    final match = _physicalLine.firstMatch(wmSizeOutput) ??
        _anySize.firstMatch(wmSizeOutput);
    if (match == null) return fallback;
    final int width = int.parse(match.group(1)!);
    final int height = int.parse(match.group(2)!);
    if (width < 1 || height < 1) return fallback;
    return height >= width ? portrait : landscape;
  }

  static final RegExp _physicalLine = RegExp(r'Physical size:\s*(\d+)x(\d+)');
  static final RegExp _anySize = RegExp(r'(\d+)x(\d+)');
}
