import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/dex_accent.dart';
import 'package:open_android_dex/ui/theme/dex_colors.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Accent colours.
///
/// The palette file already records why this needs care: blue-400 measures
/// about 2.3:1 on light paper, "which no amount of taste makes readable". So
/// every accent carries a separate, darker light-mode value, and the contrast
/// test below is the thing that stops a pretty swatch shipping unreadable.
void main() {
  /// WCAG relative luminance.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final double la = luminance(a);
    final double lb = luminance(b);
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('there is a default accent and it is first', () {
    expect(kAccents, isNotEmpty);
    expect(kAccents.first.name, 'Signal');
  });

  test('every accent is named, for the swatch tooltip and screen readers', () {
    for (final DexAccent a in kAccents) {
      expect(a.name, isNotEmpty);
    }
  });

  test('every dark accent is readable on the dark background', () {
    // 3:1 is the WCAG floor for a large-text or UI component colour, which is
    // what an accent is used as here — borders, focus rings, selected rows.
    for (final DexAccent a in kAccents) {
      expect(
        contrast(a.dark, DexColors.dark.bg),
        greaterThanOrEqualTo(3.0),
        reason: '${a.name} is unreadable on the dark desk',
      );
    }
  });

  test('every light accent is readable on the light background', () {
    // The case the palette file warns about. Borrowing the dark value here
    // measures about 2.3:1 and fails.
    for (final DexAccent a in kAccents) {
      expect(
        contrast(a.light, DexColors.light.bg),
        greaterThanOrEqualTo(3.0),
        reason: '${a.name} is unreadable on the light desk',
      );
    }
  });

  test('light accents are genuinely darker, not copies of the dark ones', () {
    for (final DexAccent a in kAccents) {
      expect(
        luminance(a.light),
        lessThan(luminance(a.dark)),
        reason: '${a.name} did not darken for light mode',
      );
    }
  });

  group('applying an accent', () {
    test('index 0 leaves the palette untouched', () {
      expect(accentFor(0, Brightness.dark), DexColors.dark.signal);
      expect(accentFor(0, Brightness.light), DexColors.light.signal);
    });

    test('an out-of-range index falls back to the default', () {
      // A stored index whose swatch no longer exists must degrade, exactly as
      // the wallpaper index already does.
      expect(accentFor(999, Brightness.dark), DexColors.dark.signal);
      expect(accentFor(-1, Brightness.dark), DexColors.dark.signal);
    });

    test('a chosen accent reaches the theme', () {
      final ThemeData t = DexTheme.dark(accentIndex: 2);
      final DexColors c = t.extension<DexColors>()!;
      expect(c.signal, kAccents[2].dark);
    });

    test('light mode takes the light value, not the dark one', () {
      final ThemeData t = DexTheme.light(accentIndex: 2);
      final DexColors c = t.extension<DexColors>()!;
      expect(c.signal, kAccents[2].light);
      expect(c.signal, isNot(kAccents[2].dark));
    });
  });
}
