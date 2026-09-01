import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/settings/desk_settings.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Reset to defaults, per section.
///
/// The point of a per-section reset is that it is *per section*: someone who
/// has made a mess of the appearance should not lose their window-snapping
/// preference to get out of it.
void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required void Function(String) record,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: DeskSettings(
          snapEnabled: false,
          onSnapChanged: (bool v) => record('snap:$v'),
          themeMode: ThemeMode.light,
          onThemeChanged: (ThemeMode m) => record('theme:${m.name}'),
          wallpaperIndex: 3,
          onWallpaperChanged: (int i) => record('wallpaper:$i'),
          accentIndex: 4,
          onAccentChanged: (int i) => record('accent:$i'),
          glassEnabled: false,
          onGlassChanged: (bool v) => record('glass:$v'),
          reduceMotion: true,
          onReduceMotionChanged: (bool v) => record('motion:$v'),
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('Appearance resets only appearance', (WidgetTester tester) async {
    final List<String> changes = <String>[];
    await pumpSettings(tester, record: changes.add);

    await tester.ensureVisible(find.byTooltip('Reset Appearance'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reset Appearance'));
    await tester.pump();

    expect(changes, contains('theme:system'));
    expect(changes, contains('accent:0'));
    expect(changes, contains('wallpaper:0'));
    expect(changes, contains('glass:true'));
    expect(changes, contains('motion:false'));
    expect(
      changes.any((String c) => c.startsWith('snap:')),
      isFalse,
      reason: 'window snapping belongs to another section',
    );
  });

  testWidgets('Desktop mode resets only desktop mode', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    await pumpSettings(tester, record: changes.add);

    await tester.ensureVisible(find.byTooltip('Reset Desktop mode'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reset Desktop mode'));
    await tester.pump();

    expect(changes, <String>['snap:true']);
  });

  testWidgets('sections with nothing to reset offer no control', (
    WidgetTester tester,
  ) async {
    // Connection and About hold no preferences. A reset button there would do
    // nothing, and a control that does nothing is worse than no control.
    await pumpSettings(tester, record: (_) {});
    expect(find.byTooltip('Reset Connection'), findsNothing);
    expect(find.byTooltip('Reset About'), findsNothing);
  });
}
