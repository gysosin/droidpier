/// Primitive design tokens for DroidPier.
///
/// Widgets must never hardcode a spacing, radius, duration, or family — read
/// them from here, so the whole surface can be retuned in one place.
library;

/// 4 px base grid. Every spacing value in the UI is one of these.
abstract final class DexSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Soft radii, on the familiar 8 / 12 / 16 step: `rounded-lg` 8, `rounded-xl`
/// 12, `rounded-2xl` 16. Glass at a tight radius reads as a sheet
/// of plastic; the softness is doing real work here, not decoration.
abstract final class DexRadius {
  /// Chips, small icon buttons, inline controls. `rounded-lg`.
  static const double control = 8;

  /// Rows, list items, buttons. `rounded-xl`.
  static const double card = 12;

  /// Dialogs and menus. `rounded-2xl`.
  static const double dialog = 16;

  /// Panels and windows — the taskbar, widgets, window frames.
  static const double panel = 16;

  /// Modal shells — the launcher, the palette, the sheet, every overlay card.
  /// The brief's scale stopped at 16; the reference ships 20 on each of these,
  /// and the rendered reference is the spec.
  static const double modal = 20;

  /// Fully round. Status dots, the gesture pill, toggle tracks.
  static const double pill = 999;
}

/// Elevation is a luminance step plus a hairline, never a drop shadow.
abstract final class DexStroke {
  static const double hairline = 1;
  static const double focusRing = 2;

  /// Collapsed width of the Link Rail's live signal trace.
  static const double railTrace = 4;
}

/// Motion budget. Animate transform and opacity only.
abstract final class DexDuration {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration enter = Duration(milliseconds: 260);

  /// Delay before a loading indicator appears, so fast paths do not flash.
  static const Duration loadingDelay = Duration(milliseconds: 200);

  /// Once shown, a loading indicator stays at least this long.
  static const Duration loadingFloor = Duration(milliseconds: 400);
}

/// Minimum interactive sizes.
///
/// This is a pointer-driven desktop application, so the applicable standard is
/// WCAG 2.2 SC 2.5.8 Target Size (Minimum) — 24×24 CSS px. Android's 48 dp rule
/// is a *touch* guideline and does not apply to a mouse-driven taskbar; where a
/// larger target is free, take it anyway.
abstract final class DexHit {
  /// Absolute floor. Nothing interactive may be smaller in either dimension.
  static const double minimum = 24;

  /// Comfortable target for small icon controls that sit among others.
  static const double comfortable = 32;

  /// Primary controls: buttons, fields, anything a person aims at first.
  static const double primary = 44;
}

/// Glyph sizes: one scale, so a tray icon is never 15 in one place and 17 in
/// another. The reference's own mapping — 14 for chrome (header pills,
/// widget headers, window controls, pins), 16 for the tray and panel bodies,
/// 20 for the control centre's toggles, 12 for the smallest inline marks,
/// 32 for an empty state's mark, 48 for a desk tile.
abstract final class DexIconSize {
  static const double inline = 12;
  static const double chrome = 14;
  static const double tray = 16;
  static const double control = 20;
  static const double ring = 24;
  static const double mark = 32;
  static const double hero = 40;
  static const double launcher = 48;
}

/// Font families.
///
/// Space Grotesk carries display, Public Sans carries body, and IBM Plex Mono
/// carries data. Data stays monospace because serials, ports and telemetry are
/// machine values and must read as such.
abstract final class DexType {
  static const String display = 'SpaceGrotesk';
  static const String body = 'PublicSans';
  static const String data = 'IBMPlexMono';

  static const List<String> displayFallback = <String>[
    'DejaVu Sans',
    'sans-serif',
  ];
  static const List<String> bodyFallback = <String>[
    'DejaVu Sans',
    'sans-serif',
  ];
  static const List<String> dataFallback = <String>[
    'DejaVu Sans Mono',
    'monospace',
  ];
}
