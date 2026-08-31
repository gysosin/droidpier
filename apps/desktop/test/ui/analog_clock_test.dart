import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/analog_clock.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

void main() {
  testWidgets('the analog clock paints without overflow and is square', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: AnalogClock(now: DateTime(2026, 8, 26, 10, 9, 36)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AnalogClock), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
    // Square, so hands and ticks stay circular.
    final Size size = tester.getSize(find.byType(AnalogClock));
    expect(size.width, size.height);
  });
}
