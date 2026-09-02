import 'package:flutter/material.dart';

/// Semantic palette for DroidPier, exposed as a [ThemeExtension] so
/// widgets read roles rather than raw values: `Theme.of(context).extension<DexColors>()!`.
///
/// Two roles are reserved and must not be used decoratively:
///   * [signal] — link state and the primary action. Blue.
///   * [trace]  — telemetry and data only. Emerald.
@immutable
class DexColors extends ThemeExtension<DexColors> {
  const DexColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.muted,
    required this.signal,
    required this.trace,
    required this.warn,
    required this.fault,
  });

  /// Window ground. Deep navy in dark, cool paper in light — never pure
  /// black and never cream. The desk paints a wallpaper over this; the
  /// value shows through only where glass is stacked deeply.
  final Color bg;

  /// Panels, drawer, taskbar.
  final Color surface;

  /// Cards, dialogs, menus — one luminance step above [surface].
  final Color raised;

  /// Hairlines, dividers, input borders.
  final Color line;

  /// Primary text.
  final Color text;

  /// Secondary text, disabled states, captions.
  final Color muted;

  /// Live link, primary action, focus ring. Blue, from the reference accent.
  final Color signal;

  /// Telemetry, throughput, charts.
  final Color trace;

  /// A reading that is worse than asked for but not a failure.
  ///
  /// Added for the health readout, which needs a caution step between "at the
  /// rate we configured" and "broken". Without one the choice was to colour a
  /// merely-slow link the same red as a dead one, which cries wolf, or the
  /// same green as a healthy one, which says nothing.
  ///
  /// Amber rather than a second blue: it has to be legible as *between* trace
  /// and fault at a glance, and only warm-to-hot reads that way.
  final Color warn;

  /// Errors and destructive actions.
  final Color fault;

  /// Values are fixed by the design system rather than chosen per widget:
  /// ground `#0B1120`, text `#F8FAFC`, and the accent family blue-400
  /// `#60A5FA` / emerald-400 `#34D399` / cyan `#22D3EE` for links, telemetry
  /// and live state respectively.
  ///
  /// This is a glass design: most panels are white at 5–15% over a
  /// blue-violet wallpaper rather than a flat fill. Those values live in
  /// [DexGlass]; what follows is the opaque substrate underneath, used where
  /// blur is unavailable or would cost too much (dense lists, goldens).
  static const DexColors dark = DexColors(
    bg: Color(0xFF0B1120),
    surface: Color(0xFF0F172A),
    raised: Color(0xFF1E293B),
    line: Color(0xFF334155),
    text: Color(0xFFF8FAFC),
    muted: Color(0xFF94A3B8),
    signal: Color(0xFF60A5FA),
    trace: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    fault: Color(0xFFFB7185),
  );

  /// The reference ships dark only. Light is derived rather than borrowed, and
  /// it stays in the same blue family instead of falling back to warm paper —
  /// a warm light mode beside this dark mode would read as two products.
  ///
  /// Every accent darkens: blue-400 measures about 2.3:1 on light paper, which
  /// no amount of taste makes readable. `signal` becomes blue-700, `trace`
  /// emerald-700, `warn` amber-700, `fault` rose-700, and `muted` slate-600 at
  /// roughly 7:1.
  static const DexColors light = DexColors(
    bg: Color(0xFFEEF2FB),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF8FAFC),
    line: Color(0xFFCBD5E1),
    text: Color(0xFF0F172A),
    muted: Color(0xFF475569),
    signal: Color(0xFF1D4ED8),
    trace: Color(0xFF047857),
    warn: Color(0xFFB45309),
    fault: Color(0xFFBE123C),
  );

  @override
  DexColors copyWith({
    Color? bg,
    Color? surface,
    Color? raised,
    Color? line,
    Color? text,
    Color? muted,
    Color? signal,
    Color? trace,
    Color? warn,
    Color? fault,
  }) {
    return DexColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      line: line ?? this.line,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      signal: signal ?? this.signal,
      trace: trace ?? this.trace,
      warn: warn ?? this.warn,
      fault: fault ?? this.fault,
    );
  }

  @override
  DexColors lerp(ThemeExtension<DexColors>? other, double t) {
    if (other is! DexColors) {
      return this;
    }
    return DexColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      signal: Color.lerp(signal, other.signal, t)!,
      trace: Color.lerp(trace, other.trace, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      fault: Color.lerp(fault, other.fault, t)!,
    );
  }
}
