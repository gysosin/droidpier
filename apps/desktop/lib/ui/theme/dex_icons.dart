import 'package:flutter/widgets.dart';

/// The product's icon vocabulary, named by what a glyph *means* here.
///
/// One place, for two reasons.
///
/// The first is consistency. `Icons` carries several drawings of the same
/// thing — filled, `_outlined`, `_rounded` — and the desk had been picking
/// between them per call site, so a filled battery sat beside an outlined
/// settings gear in the same tray. Naming the role instead of the picture
/// makes that impossible.
///
/// The second is weight. Material's default glyphs are filled shapes; Lucide
/// draws a consistent 2px stroke. Against hairline panel edges, mono readouts
/// and 1px rules, an outline set reads as instrumentation and a filled set
/// reads as a phone launcher, which is the thing this product is explicitly
/// not.
abstract final class DexIcons {
  /// The bundled Lucide face. Declared as a plain [IconData] against a font
  /// family rather than through the `lucide_icons` package: that package
  /// subclasses [IconData], which Flutter has since made `final`, so it no
  /// longer compiles. The font itself is the whole of what it offered.
  static const String _family = 'Lucide';

  // Transport and link.
  static const IconData wifi = IconData(0xf596, fontFamily: _family);
  static const IconData wifiTethering = IconData(0xf472, fontFamily: _family);
  static const IconData bluetooth = IconData(0xf1a8, fontFamily: _family);
  static const IconData usb = IconData(0xf563, fontFamily: _family);
  static const IconData cellular = IconData(0xf4d0, fontFamily: _family);
  static const IconData airplane = IconData(0xf454, fontFamily: _family);
  static const IconData location = IconData(0xf3c0, fontFamily: _family);
  static const IconData torch = IconData(0xf2ea, fontFamily: _family);
  static const IconData charging = IconData(0xf5a3, fontFamily: _family);

  // Battery.
  static const IconData battery = IconData(0xf18e, fontFamily: _family);
  static const IconData batteryFull = IconData(0xf190, fontFamily: _family);
  static const IconData batteryCharging = IconData(0xf18f, fontFamily: _family);

  // Media transport.
  static const IconData play = IconData(0xf457, fontFamily: _family);
  static const IconData pause = IconData(0xf438, fontFamily: _family);
  static const IconData previous = IconData(0xf4d6, fontFamily: _family);
  static const IconData next = IconData(0xf4d7, fontFamily: _family);
  static const IconData music = IconData(0xf403, fontFamily: _family);

  // Window chrome and navigation.
  static const IconData close = IconData(0xf59e, fontFamily: _family);
  static const IconData minimise = IconData(0xf3dc, fontFamily: _family);
  static const IconData maximise = IconData(0xf3c3, fontFamily: _family);
  static const IconData fullscreen = IconData(0xf3c4, fontFamily: _family);
  static const IconData fullscreenExit = IconData(0xf3da, fontFamily: _family);
  static const IconData back = IconData(0xf1f9, fontFamily: _family);
  static const IconData forward = IconData(0xf1fb, fontFamily: _family);
  static const IconData recents = IconData(0xf4f2, fontFamily: _family);
  static const IconData home = IconData(0xf20b, fontFamily: _family);
  static const IconData menu = IconData(0xf3ca, fontFamily: _family);
  static const IconData appsGrid = IconData(0xf38a, fontFamily: _family);
  static const IconData portrait = IconData(0xf4dd, fontFamily: _family);
  static const IconData landscape = IconData(0xf492, fontFamily: _family);
  static const IconData rotationLock = IconData(0xf3ae, fontFamily: _family);

  // Desk furniture and surfaces.
  static const IconData search = IconData(0xf4ad, fontFamily: _family);
  static const IconData microphone = IconData(0xf3d2, fontFamily: _family);
  static const IconData notifications = IconData(0xf19c, fontFamily: _family);
  static const IconData settings = IconData(0xf4b9, fontFamily: _family);
  static const IconData keyboard = IconData(0xf379, fontFamily: _family);
  static const IconData pin = IconData(0xf450, fontFamily: _family);
  static const IconData pinOff = IconData(0xf451, fontFamily: _family);
  static const IconData copy = IconData(0xf252, fontFamily: _family);
  static const IconData check = IconData(0xf1ee, fontFamily: _family);
  static const IconData unchecked = IconData(0xf20b, fontFamily: _family);
  static const IconData lightMode = IconData(0xf50f, fontFamily: _family);
  static const IconData darkMode = IconData(0xf3eb, fontFamily: _family);

  // Pairing.
  static const IconData qrCode = IconData(0xf46e, fontFamily: _family);
  static const IconData qrScan = IconData(0xf4a4, fontFamily: _family);

  // States. Fault and caution are the two the design reserves a colour for, so
  // they get distinct shapes as well: colour alone is not a signal.
  static const IconData info = IconData(0xf36e, fontFamily: _family);
  static const IconData fault = IconData(0xf10b, fontFamily: _family);
  static const IconData privacy = IconData(0xf4c0, fontFamily: _family);
  static const IconData locked = IconData(0xf3ae, fontFamily: _family);
}
