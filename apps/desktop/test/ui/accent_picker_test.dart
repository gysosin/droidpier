import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/settings/desk_settings.dart';
import 'package:open_android_dex/ui/theme/dex_accent.dart';
import 'package:open_android_dex/ui/theme/dex_colors.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Choosing an accent from Settings.
void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required int accentIndex,
    required ValueChanged<int> onAccent,
    ThemeData? theme,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? DexTheme.dark(),
        home: DeskSettings(
          snapEnabled: true,
          onSnapChanged: (_) {},
          themeMode: ThemeMode.dark,
          onThemeChanged: (_) {},
          wallpaperIndex: 0,
          onWallpaperChanged: (_) {},
          accentIndex: accentIndex,
          onAccentChanged: onAccent,
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('every accent is offered, each one named', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester, accentIndex: 0, onAccent: (_) {});
    for (final DexAccent a in kAccents) {
      expect(
        find.bySemanticsLabel(a.name),
        findsOneWidget,
        reason: '${a.name} should be reachable by name, not colour alone',
      );
    }
  });

  testWidgets('tapping a swatch reports its index', (
    WidgetTester tester,
  ) async {
    final List<int> chosen = <int>[];
    await pumpSettings(tester, accentIndex: 0, onAccent: chosen.add);

    await tester.ensureVisible(find.bySemanticsLabel(kAccents[2].name));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(kAccents[2].name));
    await tester.pump();

    expect(chosen, <int>[2]);
  });

  testWidgets('the selected swatch is the only one wearing the ring', (
    WidgetTester tester,
  ) async {
    // Asserted on the ring rather than on a semantics flag: the ring is what a
    // person actually sees, and selection has to out-contrast the rest or the
    // grid does not say which colour is in use.
    await pumpSettings(tester, accentIndex: 3, onAccent: (_) {});

    BoxDecoration decorationFor(int i) {
      final Container box = tester.widget<Container>(
        find
            .descendant(
              of: find.bySemanticsLabel(kAccents[i].name),
              matching: find.byType(Container),
            )
            .first,
      );
      return box.decoration! as BoxDecoration;
    }

    final BoxDecoration chosen = decorationFor(3);
    final BoxDecoration other = decorationFor(0);
    expect(chosen.border!.top.width, greaterThan(other.border!.top.width));
    expect(chosen.border!.top.color, isNot(other.border!.top.color));
  });

  testWidgets('light mode previews the light values', (
    WidgetTester tester,
  ) async {
    // The swatch must show the colour that will actually be used, or someone
    // picks a colour in light mode and gets a different one.
    await pumpSettings(
      tester,
      accentIndex: 0,
      onAccent: (_) {},
      theme: DexTheme.light(),
    );
    final Finder swatch = find.bySemanticsLabel(kAccents[1].name);
    final Container box = tester.widget<Container>(
      find.descendant(of: swatch, matching: find.byType(Container)).first,
    );
    final BoxDecoration decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, kAccents[1].light);
    expect(decoration.color, isNot(kAccents[1].dark));
  });

  testWidgets('an accent reaches the theme the shell renders with', (
    WidgetTester tester,
  ) async {
    final ThemeData t = DexTheme.dark(accentIndex: 4);
    expect(t.extension<DexColors>()!.signal, kAccents[4].dark);
  });
}
