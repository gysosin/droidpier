import 'package:flutter/widgets.dart';

/// A named desk wallpaper: the diagonal gradient the desk is painted with.
///
/// Kept as plain colour lists so a choice is cheap to carry and draw — the
/// wallpaper is [DeskWallpaper], which layers a bloom and a vignette over
/// whatever gradient it is given.
@immutable
class DexWallpaperChoice {
  const DexWallpaperChoice({required this.name, required this.colors});

  final String name;
  final List<Color> colors;
}

/// The wallpapers a person can pick in Settings.
///
/// The first is the default blue→indigo→violet; the rest give the desk a
/// different mood without leaving the dark, saturated family the glass reads
/// well over.
const List<DexWallpaperChoice> kWallpaperChoices = <DexWallpaperChoice>[
  // Named after the phone companion's wallpaper set. Painted as rich diagonal
  // gradients rather than photographs, which we cannot ship.
  DexWallpaperChoice(
    name: 'Deep Midnight',
    colors: <Color>[Color(0xFF0B2A3A), Color(0xFF0F766E), Color(0xFF1E3A8A)],
  ),
  DexWallpaperChoice(
    name: 'Nordic Aurora',
    colors: <Color>[Color(0xFF3B1F53), Color(0xFF7C3AED), Color(0xFFDB2777)],
  ),
  DexWallpaperChoice(
    name: 'Volcanic Sunset',
    colors: <Color>[Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFF9D174D)],
  ),
  DexWallpaperChoice(
    name: 'Mist Canopy',
    colors: <Color>[Color(0xFF1E293B), Color(0xFF6B5B95), Color(0xFFA78BBA)],
  ),
  DexWallpaperChoice(
    name: 'Slate',
    colors: <Color>[Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
  ),
  DexWallpaperChoice(
    name: 'Forest',
    colors: <Color>[Color(0xFF052E16), Color(0xFF14532D), Color(0xFF166534)],
  ),
];

/// Carries the chosen wallpaper down to [DeskWallpaper].
///
/// When absent, or when [colors] is null, the wallpaper falls back to the
/// theme's own gradient — so nothing outside a desk needs to know this exists.
class WallpaperScope extends InheritedWidget {
  const WallpaperScope({required this.colors, required super.child, super.key});

  /// The gradient to paint, or null to use the theme default.
  final List<Color>? colors;

  static List<Color>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WallpaperScope>()
      ?.colors;

  @override
  bool updateShouldNotify(WallpaperScope oldWidget) => colors != oldWidget.colors;
}
