import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The frosted-glass layer, kept separate from [DexColors] because it is a
/// different kind of value: these are *alphas over a wallpaper*, not opaque
/// roles, and almost every one of them is white.
///
/// The whole surface language is built from three fills and two strokes.
/// Holding to exactly those is what makes the desk read as glass rather than
/// as flat panels with a blur bolted on.
@immutable
class DexGlass extends ThemeExtension<DexGlass> {
  const DexGlass({
    required this.fill,
    required this.fillStrong,
    required this.fillSubtle,
    required this.substrate,
    required this.stroke,
    required this.strokeStrong,
    required this.blur,
    required this.wallpaper,
    required this.bloom,
    required this.vignette,
  });

  /// Standard panel: white at 8%. Taskbar entries, widgets, drawer rows.
  final Color fill;

  /// Hover and pressed states, and controls that must read as raised.
  /// Out-contrasts [fill] deliberately — a hover that does not brighten is
  /// not a hover.
  final Color fillStrong;

  /// Backing for content that sits *inside* another glass panel, where a
  /// second 8% layer would stack into opacity.
  final Color fillSubtle;

  /// Dark glass for surfaces that must stay legible over a bright wallpaper:
  /// menus, dialogs, the app drawer. Slate at 65% rather than white.
  final Color substrate;

  /// Hairline on every glass edge. White at 20%.
  final Color stroke;

  /// The focused-window ring and the keyboard focus indicator. White at 40%,
  /// so focus is visible against [stroke] without a colour change.
  final Color strokeStrong;

  /// Backdrop blur sigma. The reference blurs 24px and saturates 180%;
  /// Flutter has no cheap saturation filter, so the fills are nudged instead.
  final double blur;

  /// The desk wallpaper: blue → indigo → violet, top-left to bottom-right.
  final List<Color> wallpaper;

  /// Radial highlight from the top-right corner.
  final Color bloom;

  /// Darkening toward the bottom, so the taskbar has something to sit on.
  final Color vignette;

  static const DexGlass dark = DexGlass(
    fill: Color(0x14FFFFFF),
    fillStrong: Color(0x33FFFFFF),
    fillSubtle: Color(0x0DFFFFFF),
    substrate: Color(0xA60F172A),
    stroke: Color(0x33FFFFFF),
    strokeStrong: Color(0x66FFFFFF),
    blur: 24,
    wallpaper: <Color>[Color(0xFF1E3A8A), Color(0xFF1E40AF), Color(0xFF7C3AED)],
    bloom: Color(0x26FFFFFF),
    vignette: Color(0x4D000000),
  );

  /// Light glass inverts what is tinted. White at 8% over pale paper is
  /// invisible, so panels darken instead and the wallpaper desaturates —
  /// the same design, not a second one.
  static const DexGlass light = DexGlass(
    fill: Color(0xB8FFFFFF),
    fillStrong: Color(0xF2FFFFFF),
    fillSubtle: Color(0x8AFFFFFF),
    substrate: Color(0xF2FFFFFF),
    stroke: Color(0x1F0F172A),
    strokeStrong: Color(0x520F172A),
    blur: 24,
    wallpaper: <Color>[Color(0xFFBFD4F5), Color(0xFFC7D2FE), Color(0xFFDCC9F7)],
    bloom: Color(0x66FFFFFF),
    vignette: Color(0x140F172A),
  );

  @override
  DexGlass copyWith({
    Color? fill,
    Color? fillStrong,
    Color? fillSubtle,
    Color? substrate,
    Color? stroke,
    Color? strokeStrong,
    double? blur,
    List<Color>? wallpaper,
    Color? bloom,
    Color? vignette,
  }) {
    return DexGlass(
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      fillSubtle: fillSubtle ?? this.fillSubtle,
      substrate: substrate ?? this.substrate,
      stroke: stroke ?? this.stroke,
      strokeStrong: strokeStrong ?? this.strokeStrong,
      blur: blur ?? this.blur,
      wallpaper: wallpaper ?? this.wallpaper,
      bloom: bloom ?? this.bloom,
      vignette: vignette ?? this.vignette,
    );
  }

  @override
  DexGlass lerp(ThemeExtension<DexGlass>? other, double t) {
    if (other is! DexGlass) return this;
    return DexGlass(
      fill: Color.lerp(fill, other.fill, t)!,
      fillStrong: Color.lerp(fillStrong, other.fillStrong, t)!,
      fillSubtle: Color.lerp(fillSubtle, other.fillSubtle, t)!,
      substrate: Color.lerp(substrate, other.substrate, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      strokeStrong: Color.lerp(strokeStrong, other.strokeStrong, t)!,
      blur: ui.lerpDouble(blur, other.blur, t)!,
      wallpaper: <Color>[
        for (var i = 0; i < wallpaper.length; i++)
          Color.lerp(wallpaper[i], other.wallpaper[i], t)!,
      ],
      bloom: Color.lerp(bloom, other.bloom, t)!,
      vignette: Color.lerp(vignette, other.vignette, t)!,
    );
  }

  static DexGlass of(BuildContext context) =>
      Theme.of(context).extension<DexGlass>() ?? dark;
}
