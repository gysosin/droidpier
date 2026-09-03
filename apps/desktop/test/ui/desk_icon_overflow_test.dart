import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/desk/desk_icons.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Desk icons with names long enough to wrap.
///
/// The tile is a fixed height holding a 48px glyph, a gap and up to two lines
/// of label. Every test that rendered it passed a name short enough to fit on
/// one line, so a two-line name — "Ball Sort Puzzle" is enough — overflowed the
/// box by six pixels and put a striped banner where the app should be.
///
/// It was found by running the product, not by the suite. This is the suite
/// catching up.
void main() {
  Future<Object?> pumpNames(WidgetTester tester, List<String> labels) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: DeskIcons(
            applications: <AndroidApplication>[
              for (final String l in labels)
                AndroidApplication(
                  packageName: 'com.example.${l.hashCode}',
                  label: l,
                ),
            ],
            onLaunch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return tester.takeException();
  }

  testWidgets('a two-line name does not overflow its tile', (
    WidgetTester tester,
  ) async {
    expect(await pumpNames(tester, <String>['Ball Sort Puzzle']), isNull);
  });

  testWidgets('a very long single word does not overflow either', (
    WidgetTester tester,
  ) async {
    // No wrap opportunity at all, which is the other way a label misbehaves.
    expect(
      await pumpNames(tester, <String>['Antidisestablishmentarianism']),
      isNull,
    );
  });

  testWidgets('a grid of mixed-length names stays clean', (
    WidgetTester tester,
  ) async {
    expect(
      await pumpNames(tester, <String>[
        'Airtel',
        'Ball Sort Puzzle',
        'Authenticator',
        'Calculator',
        'Google Play services for Instant Apps',
        'M',
      ]),
      isNull,
    );
  });
}
