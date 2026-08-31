import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/motion/sustained.dart';

/// The recovery overlay covers the whole desk at 92% opacity. Toggling it on
/// the raw transport phase meant a link that dipped in and out of recovery
/// flashed the entire screen, which showed up as blinking.
void main() {
  Future<void> pump(WidgetTester tester, bool visible) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Sustained(
          visible: visible,
          delay: const Duration(milliseconds: 200),
          floor: const Duration(milliseconds: 400),
          child: const Text('overlay'),
        ),
      ),
    );
  }

  testWidgets('a blip shorter than the delay shows nothing at all', (
    WidgetTester tester,
  ) async {
    await pump(tester, true);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('overlay'), findsNothing);

    await pump(tester, false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.text('overlay'),
      findsNothing,
      reason: 'it must never have appeared',
    );
  });

  testWidgets('a real outage shows the overlay', (WidgetTester tester) async {
    await pump(tester, true);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('overlay'), findsOneWidget);

    await pump(tester, false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('overlay'), findsNothing);
  });

  testWidgets('once shown it stays long enough to be read', (
    WidgetTester tester,
  ) async {
    await pump(tester, true);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('overlay'), findsOneWidget);

    // Recovered almost immediately after the overlay appeared.
    await pump(tester, false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('overlay'),
      findsOneWidget,
      reason: 'flashing it away instantly is the same blink in reverse',
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('overlay'), findsNothing);
  });
}
