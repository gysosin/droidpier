import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/companion/companion_view.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// The companion view is a picture of the phone's app, but the numbers on it
/// are this desk's: which computer the phone is linked to, and for how long.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? hostName,
    DateTime? linkSince,
    required DateTime now,
  }) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Center(
            child: CompanionView(
              snapshot: facade.snapshot,
              hostName: hostName,
              linkSince: linkSince,
              now: now,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets("names the computer and counts the link's age", (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 9, 5, 12, 0, 0);
    await pump(
      tester,
      hostName: 'workbench',
      linkSince: now.subtract(
        const Duration(hours: 1, minutes: 42, seconds: 18),
      ),
      now: now,
    );
    expect(find.text('workbench'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('01h 42m 18s'), findsOneWidget);
    expect(find.text('LINK RATE'), findsOneWidget);
  });

  testWidgets('without a link it says so, without inventing a duration', (
    WidgetTester tester,
  ) async {
    await pump(tester, now: DateTime(2026, 9, 5, 12));
    expect(find.text('This computer'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('fits a short window instead of overflowing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester, now: DateTime(2026, 9, 5, 12));
    expect(tester.takeException(), isNull);
    final Size frame = tester.getSize(find.byType(CompanionView));
    expect(frame.height, lessThanOrEqualTo(600 * 0.85));
  });
}
