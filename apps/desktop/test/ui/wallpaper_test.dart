import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/glass.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/theme/wallpapers.dart';

/// The chosen wallpaper must actually reach the desk gradient.
void main() {
  LinearGradient wallpaperGradient(WidgetTester tester) {
    // The outer DecoratedBox of DeskWallpaper carries the linear gradient.
    final DecoratedBox box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(DeskWallpaper),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    return (box.decoration as BoxDecoration).gradient! as LinearGradient;
  }

  testWidgets('a WallpaperScope override paints its own gradient', (
    WidgetTester tester,
  ) async {
    const List<Color> custom = <Color>[
      Color(0xFF111111),
      Color(0xFF222222),
      Color(0xFF333333),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: const WallpaperScope(
          colors: custom,
          child: DeskWallpaper(child: SizedBox()),
        ),
      ),
    );
    expect(wallpaperGradient(tester).colors, custom);
  });

  testWidgets('without a scope, the theme default gradient is used', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: const DeskWallpaper(child: SizedBox()),
      ),
    );
    // Without a WallpaperScope, DeskWallpaper paints the theme's own wallpaper
    // gradient (DexGlass.wallpaper), not a picker preset.
    expect(
      wallpaperGradient(tester).colors,
      const <Color>[Color(0xFF1E3A8A), Color(0xFF1E40AF), Color(0xFF7C3AED)],
    );
  });
}
