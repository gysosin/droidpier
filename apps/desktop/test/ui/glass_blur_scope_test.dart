import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/glass.dart';

/// Backdrop blur must switch off under a disabled [GlassBlurScope].
///
/// A BackdropFilter re-blurs its backdrop every frame the backdrop changes, so
/// glass panels over a live 60 fps video texture re-blur the whole scene
/// continuously — the desk flicker. The desk disables the scope while a window
/// streams; this guards that a panel then paints no BackdropFilter at all.
void main() {
  Finder backdrops() => find.byType(BackdropFilter);

  testWidgets('a panel blurs when the scope allows it (the default)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassBlurScope(
          enabled: true,
          child: GlassPanel(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );
    expect(backdrops(), findsOneWidget);
  });

  testWidgets('a panel paints no BackdropFilter when the scope is disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassBlurScope(
          enabled: false,
          child: GlassPanel(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );
    expect(
      backdrops(),
      findsNothing,
      reason: 'while streaming, no glass panel may re-blur the video',
    );
  });

  testWidgets('with no scope at all, a panel still blurs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassPanel(child: SizedBox(width: 40, height: 40)),
      ),
    );
    expect(backdrops(), findsOneWidget);
  });
}
