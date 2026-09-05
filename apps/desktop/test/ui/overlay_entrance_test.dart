import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/motion/dex_motion.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Every overlay opens with the same short entrance: a scrim that fades in,
/// a card that fades and scales in. Once it has arrived nothing keeps
/// animating, and reduced motion skips it entirely.
void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    theme: DexTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  double opacityOf(WidgetTester tester, String text) => tester
      .widget<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
      )
      .opacity;

  testWidgets('a card fades and scales in, then rests', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const OverlayEntrance.card(child: Text('card'))),
    );
    // First frame: not yet there.
    expect(opacityOf(tester, 'card'), lessThan(1));
    expect(
      find.ancestor(of: find.text('card'), matching: find.byType(Transform)),
      findsOneWidget,
      reason: 'a card scales in as well as fading',
    );

    // Settling proves the entrance ends: a perpetual animation would time
    // this out, and a finished one leaves no frame scheduled.
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'card'), 1);
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'an overlay that has arrived must cost nothing to keep',
    );
  });

  testWidgets('a scrim only fades', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(const OverlayEntrance.scrim(child: Text('scrim'))),
    );
    expect(opacityOf(tester, 'scrim'), lessThan(1));
    expect(
      find.ancestor(of: find.text('scrim'), matching: find.byType(Transform)),
      findsNothing,
      reason: 'a scrim fades; scaling a full-screen tint is nonsense',
    );
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'scrim'), 1);
  });

  testWidgets('reduced motion arrives at once', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(const OverlayEntrance.card(child: Text('card')), reduceMotion: true),
    );
    expect(opacityOf(tester, 'card'), 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
