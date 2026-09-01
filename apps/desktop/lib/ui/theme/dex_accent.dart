import 'package:flutter/widgets.dart';

import 'dex_colors.dart';

/// One accent choice, in both themes.
///
/// Two values rather than one, and not for taste. `dex_colors.dart` records the
/// measurement: blue-400 sits at about 2.3:1 on light paper, "which no amount
/// of taste makes readable". Every accent therefore carries a darker light-mode
/// value, and `accent_test.dart` holds each of them to a 3:1 floor against the
/// background it actually appears on.
@immutable
class DexAccent {
  const DexAccent({
    required this.name,
    required this.dark,
    required this.light,
  });

  /// Shown in the swatch tooltip and read aloud by a screen reader. A grid of
  /// unlabelled colours is unusable to anyone who cannot see them.
  final String name;

  /// For the dark desk.
  final Color dark;

  /// For the light desk. Always the darker of the two.
  final Color light;
}

/// The curated set. Index 0 is the product's own blue and is the default, so a
/// stored 0 means "unchanged" and needs no special case.
const List<DexAccent> kAccents = <DexAccent>[
  DexAccent(
    name: 'Signal',
    dark: Color(0xFF60A5FA), // blue-400, the shipped default
    light: Color(0xFF1D4ED8), // blue-700
  ),
  DexAccent(
    name: 'Phosphor',
    dark: Color(0xFFFBBF24), // amber-400 — the Phosphor Bench reference
    light: Color(0xFF92400E), // amber-800; amber needs more darkening than most
  ),
  DexAccent(
    name: 'Trace',
    dark: Color(0xFF34D399), // emerald-400
    light: Color(0xFF047857), // emerald-700
  ),
  DexAccent(
    name: 'Violet',
    dark: Color(0xFFA78BFA), // violet-400
    light: Color(0xFF6D28D9), // violet-700
  ),
  DexAccent(
    name: 'Rose',
    dark: Color(0xFFFB7185), // rose-400
    light: Color(0xFFBE123C), // rose-700
  ),
  DexAccent(
    name: 'Slate',
    dark: Color(0xFF94A3B8), // slate-400, for anyone who wants no colour at all
    light: Color(0xFF475569), // slate-600
  ),
];

/// The signal colour for [index] in [brightness].
///
/// An index with no swatch behind it falls back to the default rather than
/// throwing, exactly as the stored wallpaper index already does — a settings
/// file is not worth crashing the desk over.
Color accentFor(int index, Brightness brightness) {
  final DexAccent accent = (index >= 0 && index < kAccents.length)
      ? kAccents[index]
      : kAccents.first;
  return brightness == Brightness.dark ? accent.dark : accent.light;
}

/// [base] with its signal colour replaced by accent [index].
DexColors withAccent(DexColors base, int index, Brightness brightness) =>
    base.copyWith(signal: accentFor(index, brightness));
