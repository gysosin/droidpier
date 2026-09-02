import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/diagnostics/health_hud.dart';
import 'package:open_android_dex/ui/theme/dex_colors.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// A glanceable read on whether the link is healthy.
///
/// The thresholds are the ones recorded in the plan, not invented here: 50 and
/// 25 frames a second, 50 ms and 150 ms of latency. The tests assert against
/// those numbers so a later edit to the widget cannot quietly move the bar.
void main() {
  group('grading', () {
    test('frames are graded against the configured rate, not against zero', () {
      expect(gradeFps(60), HealthGrade.good);
      expect(gradeFps(50), HealthGrade.good);
      expect(gradeFps(49), HealthGrade.fair);
      expect(gradeFps(25), HealthGrade.fair);
      expect(gradeFps(24), HealthGrade.poor);
      expect(gradeFps(0), HealthGrade.poor);
    });

    test('an unmeasured rate is not graded as bad', () {
      // Null means no completed sample. Colouring it red would report a fault
      // from an absence, which is the mistake the stall notice already had to
      // be corrected for.
      expect(gradeFps(null), HealthGrade.unknown);
      expect(gradeLatency(null), HealthGrade.unknown);
    });

    test('latency is graded on how attached a tap feels', () {
      expect(gradeLatency(20), HealthGrade.good);
      expect(gradeLatency(49), HealthGrade.good);
      expect(gradeLatency(50), HealthGrade.fair);
      expect(gradeLatency(150), HealthGrade.fair);
      expect(gradeLatency(151), HealthGrade.poor);
    });
  });

  group('widget', () {
    Future<void> pump(
      WidgetTester tester, {
      double? fps,
      double? latencyMs,
      String? windowLabel,
    }) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: DexTheme.dark(),
          home: Scaffold(
            body: HealthHud(
              framesPerSecond: fps,
              latency: latencyMs == null
                  ? null
                  : TelemetryMeasurement(
                      value: latencyMs,
                      unit: TelemetryUnit.milliseconds,
                    ),
              throughput: const TelemetryMeasurement(
                value: 2400000,
                unit: TelemetryUnit.bytesPerSecond,
              ),
              windowLabel: windowLabel,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('it reports the rate it was given', (
      WidgetTester tester,
    ) async {
      await pump(tester, fps: 58.4, latencyMs: 24);
      expect(find.textContaining('58'), findsOneWidget);
    });

    testWidgets('it names the window whose rate it is showing', (
      WidgetTester tester,
    ) async {
      // Per-window when one is focused, so the number is attributable.
      await pump(tester, fps: 58.4, latencyMs: 24, windowLabel: 'Maps');
      expect(find.textContaining('Maps'), findsOneWidget);
    });

    testWidgets('an unmeasured rate is said, not shown as zero', (
      WidgetTester tester,
    ) async {
      await pump(tester, latencyMs: 24);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.textContaining('—'), findsWidgets);
    });

    testWidgets('throughput carries no colour of its own', (
      WidgetTester tester,
    ) async {
      // A low number on a still screen is correct behaviour; colouring it
      // would invent a fault out of an idle desk.
      await pump(tester, fps: 58.4, latencyMs: 24);
      final DexColors c = DexTheme.dark().extension<DexColors>()!;
      final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
      final Text throughput = texts.firstWhere(
        (Text t) => (t.data ?? '').contains('MB/s'),
      );
      expect(throughput.style?.color, isNot(c.fault));
    });
  });
}
