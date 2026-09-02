import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
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

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.md,
        vertical: DexSpace.sm,
      ),
      decoration: BoxDecoration(
        // Opaque, not frosted. A BackdropFilter here would re-blur the video
        // behind it on every frame.
        color: c.bg.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: c.line, width: DexStroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (windowLabel case final String label) ...<Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DexTheme.data(c, size: 11, color: c.muted),
            ),
            const SizedBox(width: DexSpace.md),
          ],
          _Reading(
            label: 'fps',
            value: framesPerSecond == null
                ? '—'
                : framesPerSecond!.toStringAsFixed(1),
            grade: gradeFps(framesPerSecond),
            colors: c,
          ),
          const SizedBox(width: DexSpace.md),
          _Reading(
            label: 'lat',
            value: latency == null
                ? '—'
                : '${latency!.value.round()} ms',
            grade: gradeLatency(latency?.value),
            colors: c,
          ),
          const SizedBox(width: DexSpace.md),
          // No grade. Throughput is a bandwidth reading, not a health signal:
          // a low number on a still screen is correct, and colouring it would
          // invent a fault out of an idle desk.
          _Reading(
            label: 'rate',
            value: throughput == null ? '—' : _bytes(throughput!.value),
            grade: HealthGrade.unknown,
            colors: c,
          ),
        ],
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

class _Reading extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.value,
    required this.grade,
    required this.colors,
  });

  final String label;
  final String value;
  final HealthGrade grade;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final Color tint = switch (grade) {
      // trace, not signal. `trace` is the palette's telemetry green and this is
      // telemetry; `signal` is the accent blue, which beside amber and red
      // stops reading as the top of a traffic light and starts reading as a
      // fourth, unrelated state.
      HealthGrade.good => colors.trace,
      HealthGrade.fair => colors.warn,
      HealthGrade.poor => colors.fault,
      HealthGrade.unknown => colors.text,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: DexTheme.data(colors, size: 10, color: colors.muted)),
        const SizedBox(width: DexSpace.xs),
        // Tabular, so a rate crossing 9.9 to 10.0 does not shift the row.
        SwapText(value, style: DexTheme.data(colors, size: 12, color: tint)),
      ],
    );
  }
}
