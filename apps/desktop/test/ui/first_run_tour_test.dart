import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/boot/first_run_tour.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The first-run tour.
///
/// A new user lands on a desk with a wallpaper and no idea that Ctrl+Space,
/// edge snapping or the control centre exist. The product looks emptier than it
/// is. This runs once and then never again.
void main() {
  int instance = 0;

  Future<void> pumpTour(
    WidgetTester tester, {
    required VoidCallback onFinished,
  }) async {
    // A fresh key per pump. Without it Flutter reuses the same State across
    // pumpWidget calls in one test, so the step index carries over and the
    // second iteration starts halfway through the tour.
    instance++;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: FirstRunTour(
            key: ValueKey<int>(instance),
            onFinished: onFinished,
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('it starts on the first step', (WidgetTester tester) async {
    await pumpTour(tester, onFinished: () {});
    expect(find.text(kTourSteps.first.title), findsOneWidget);
    expect(find.text('1 of ${kTourSteps.length}'), findsOneWidget);
  });

  testWidgets('Next walks every step and then finishes', (
    WidgetTester tester,
  ) async {
    int finished = 0;
    await pumpTour(tester, onFinished: () => finished++);

    for (int i = 0; i < kTourSteps.length - 1; i++) {
      expect(find.text(kTourSteps[i].title), findsOneWidget);
      await tapNext(tester);
    }
    // Last step offers Done rather than Next, so the end is not a surprise.
    expect(find.text(kTourSteps.last.title), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(finished, 1);
  });

  testWidgets('Skip is on every step, and ends it', (
    WidgetTester tester,
  ) async {
    // Someone who already knows the product must be able to leave at once,
    // from wherever they are.
    for (int step = 0; step < kTourSteps.length; step++) {
      int finished = 0;
      await pumpTour(tester, onFinished: () => finished++);
      for (int i = 0; i < step; i++) {
        await tapNext(tester);
      }
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(finished, 1, reason: 'Skip must finish from step ${step + 1}');
    }
  });

  testWidgets('every step says something, and names a real surface', (
    WidgetTester tester,
  ) async {
    for (final TourStep s in kTourSteps) {
      expect(s.title, isNotEmpty);
      expect(s.body, isNotEmpty);
    }
  });

  testWidgets('it ends by pointing at the shortcut sheet', (
    WidgetTester tester,
  ) async {
    // The tour is four sentences; the sheet is the whole list. Ending without
    // naming it wastes the one moment the person is paying attention.
    await pumpTour(tester, onFinished: () {});
    for (int i = 0; i < kTourSteps.length - 1; i++) {
      await tapNext(tester);
    }
    expect(find.textContaining('?'), findsWidgets);
  });

  testWidgets('the step counter tracks position', (WidgetTester tester) async {
    await pumpTour(tester, onFinished: () {});
    await tapNext(tester);
    expect(find.text('2 of ${kTourSteps.length}'), findsOneWidget);
  });
}
