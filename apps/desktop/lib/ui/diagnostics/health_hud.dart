import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';

/// How a reading compares to what the product asks of it.
enum HealthGrade { good, fair, poor, unknown }

/// Frames per second, graded against the configured rate.
///
/// The stream is set up for 60, so the bar is set against that rather than
/// against a generic "is it moving" test. Thresholds are the ones recorded in
/// `docs/plans/10-connection-health-hud.md`; they are not chosen here, and a
/// test asserts these exact numbers so a later edit cannot quietly move them.
///
/// A still screen legitimately presents few frames — the rate counts changes,
/// not capability — so a low grade is a reading, never an accusation.
HealthGrade gradeFps(double? fps) => switch (fps) {
  null => HealthGrade.unknown,
  final double f when f >= 50 => HealthGrade.good,
  final double f when f >= 25 => HealthGrade.fair,
  _ => HealthGrade.poor,
};

/// Link latency, graded on how attached a tap feels.
HealthGrade gradeLatency(double? ms) => switch (ms) {
  null => HealthGrade.unknown,
  final double v when v < 50 => HealthGrade.good,
  final double v when v <= 150 => HealthGrade.fair,
  _ => HealthGrade.poor,
};

/// A glanceable read on whether the link is healthy.
///
/// Deliberately small and deliberately quiet: it sits over a live video
/// texture, so it paints flat colour and text and nothing else. No blur, no
/// shadow, no animation — every one of those costs a composite over the stream
/// it is reporting on, which would make the readout the reason the number
/// drops.
class HealthHud extends StatelessWidget {
  const HealthHud({
    required this.framesPerSecond,
    required this.latency,
    required this.throughput,
    this.windowLabel,
    super.key,
  });

  final double? framesPerSecond;
  final TelemetryMeasurement? latency;
  final TelemetryMeasurement? throughput;

  /// The focused window's name, when there is one. Per-window rates are only
  /// useful if you can tell which window they belong to.
  final String? windowLabel;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final HealthGrade grade = gradeFps(framesPerSecond);
    final Color dot = switch (grade) {
      HealthGrade.good => c.trace,
      HealthGrade.fair => c.warn,
      HealthGrade.poor => c.fault,
      HealthGrade.unknown => c.muted,
    };

    // One line, solid, no blur, no pointer. This is the zero-overhead readout:
    // it sits over live video and must cost nothing to keep there.
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DexSpace.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(DexRadius.control),
          border: Border.all(color: c.line, width: DexStroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
            const SizedBox(width: DexSpace.sm),
            Text(
              framesPerSecond == null
                  ? '\u2014 fps'
                  : '${framesPerSecond!.round()} fps',
              style: DexTheme.data(
                c,
                size: 11,
                color: c.text,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: DexSpace.md),
            Text(
              'RTT: ${latency == null ? '\u2014' : '${latency!.value.round()}ms'}',
              style: DexTheme.data(c, size: 11),
            ),
            const SizedBox(width: DexSpace.md),
            Text(
              'TX: ${throughput == null ? '\u2014' : _bytes(throughput!.value)}',
              style: DexTheme.data(c, size: 11),
            ),
            if (windowLabel case final String label) ...<Widget>[
              const SizedBox(width: DexSpace.md),
              Text('Target: $label', style: DexTheme.data(c, size: 11)),
            ],
          ],
        ),
      ),
    );
  }

  static String _bytes(double perSecond) {
    if (perSecond >= 1000000) {
      return '${(perSecond / 1000000).toStringAsFixed(1)} MB/s';
    }
    if (perSecond >= 1000) {
      return '${(perSecond / 1000).toStringAsFixed(0)} kB/s';
    }
    return '${perSecond.round()} B/s';
  }
}
