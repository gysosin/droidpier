import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';
import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../util/error_guidance.dart';

// The small pieces the connection screen's three panels share.
//
// They live together because the panels have to look like one surface: a field
// on the manual tab and a field on the connect-port step are the same control,
// and a failure on the nearby tab reads the same as a failure on the QR tab.

/// A framed region with a heading — the composition unit of the screen.
class ConnectPanel extends StatelessWidget {
  const ConnectPanel({
    required this.title,
    required this.child,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(DexRadius.dialog),
        border: Border.all(color: c.line, width: DexStroke.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: t.titleSmall),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(subtitle!, style: t.bodySmall?.copyWith(color: c.muted)),
          ],
          const SizedBox(height: DexSpace.md),
          // Not wrapped in Flexible on purpose: the narrow layout stacks these
          // panels inside a scroll view, where a flex child under unbounded
          // height constraints throws. Panels that need a ceiling set their own.
          child,
        ],
      ),
    );
  }
}

/// A state with nothing in it that still says what to do about that.
class ConnectNotice extends StatelessWidget {
  const ConnectNotice({
    required this.title,
    required this.detail,
    this.action,
    super.key,
  });

  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: c.line, width: DexStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: t.bodyLarge),
          const SizedBox(height: DexSpace.xs),
          Text(detail, style: t.bodyMedium?.copyWith(color: c.muted)),
          if (action != null) ...<Widget>[
            const SizedBox(height: DexSpace.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A typed failure, shown where it happened.
///
/// [OpenDexError.message] only. `technicalDetails` is diagnostic information
/// for logs and is deliberately unreachable from here — there is no parameter
/// that could carry it in.
class InlineError extends StatelessWidget {
  const InlineError({required this.error, this.guidance, super.key});

  final OpenDexError error;

  /// What to do next, in the product's words. The backend says what went
  /// wrong; this says what the person can do about it.
  ///
  /// Left null, the shared advice for this error code is used. Passing a
  /// string overrides it, for the places that know something the code alone
  /// does not — a pairing screen can say the phone shows a fresh code each
  /// time, which is true there and nowhere else.
  final String? guidance;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DexSpace.md),
        decoration: BoxDecoration(
          color: c.fault.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(DexRadius.card),
          border: Border.all(color: c.fault, width: DexStroke.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(DexIcons.fault, size: 16, color: c.fault),
            const SizedBox(width: DexSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    error.message,
                    style: t.bodyMedium?.copyWith(color: c.text),
                  ),
                  if (guidance ?? guidanceFor(error) case final String advice)
                    ...<Widget>[
                      const SizedBox(height: DexSpace.xs),
                      Text(
                        advice,
                        style: t.bodySmall?.copyWith(color: c.muted),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A neutral, non-error explanation that stays on screen.
class ConnectHint extends StatelessWidget {
  const ConnectHint({required this.text, this.icon, super.key});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon ?? DexIcons.info, size: 14, color: c.muted),
        const SizedBox(width: DexSpace.sm),
        Expanded(
          child: Text(
            text,
            style: t.bodySmall?.copyWith(color: c.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// A machine value copied off the phone. Mono, because addresses, ports and
/// codes are compared digit by digit.
class ConnectField extends StatelessWidget {
  const ConnectField({
    required this.label,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.obscure = false,
    this.digitsOnly = false,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool obscure;
  final bool digitsOnly;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DexRadius.control),
      borderSide: BorderSide(color: c.line, width: DexStroke.hairline),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelLarge),
        const SizedBox(height: DexSpace.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DexHit.primary),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            obscureText: obscure,
            // A one-time code is not a password to remember and not a word to
            // correct: keep it away from suggestion, autofill, and IME
            // learning stores entirely.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const <String>[],
            keyboardType: digitsOnly
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: <TextInputFormatter>[
              // Digits only, and *kept as digits* — never parsed to an int and
              // formatted back, which is how a code like 004821 would silently
              // become 4821.
              if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
              if (maxLength != null)
                LengthLimitingTextInputFormatter(maxLength),
            ],
            textInputAction: onSubmitted == null
                ? TextInputAction.next
                : TextInputAction.done,
            style: DexTheme.data(c, color: c.text),
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted?.call(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: c.raised,
              hintText: hint,
              hintStyle: DexTheme.data(c),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DexSpace.md,
                vertical: DexSpace.md,
              ),
              border: border,
              enabledBorder: border,
              // Focus out-contrasts rest, always visibly.
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DexRadius.control),
                borderSide: BorderSide(
                  color: c.signal,
                  width: DexStroke.focusRing,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A value carried over from an earlier step. Shown, not re-asked.
class ConnectReadout extends StatelessWidget {
  const ConnectReadout({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelLarge),
        const SizedBox(height: DexSpace.xs),
        Container(
          height: DexHit.primary,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: DexSpace.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(DexRadius.control),
            border: Border.all(color: c.line, width: DexStroke.hairline),
          ),
          child: Text(value, style: DexTheme.data(c, color: c.text)),
        ),
      ],
    );
  }
}

/// Two fields side by side when there is room, stacked when there is not.
class ConnectFieldRow extends StatelessWidget {
  const ConnectFieldRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: DexSpace.md),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: DexSpace.md),
              Expanded(flex: i == 0 ? 3 : 2, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Which of the three ways in the person is looking at.
enum WirelessMode { nearby, qr, manual }

/// The mode switch: one row of segments, the selected one out-contrasting both
/// hover and rest.
class WirelessModeBar extends StatelessWidget {
  const WirelessModeBar({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final WirelessMode mode;
  final ValueChanged<WirelessMode> onChanged;

  static (String, IconData) describe(WirelessMode m) => switch (m) {
    WirelessMode.nearby => ('Nearby', DexIcons.wifiTethering),
    WirelessMode.qr => ('QR code', DexIcons.qrCode),
    WirelessMode.manual => ('Manual', DexIcons.keyboard),
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Container(
      padding: const EdgeInsets.all(DexSpace.xs),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(DexRadius.control),
        border: Border.all(color: c.line, width: DexStroke.hairline),
      ),
      // Equal thirds rather than intrinsic widths: this bar spans the panel,
      // and three segments that resize as their labels change would make the
      // selected one look like it moved.
      child: Row(
        children: <Widget>[
          for (final WirelessMode m in WirelessMode.values)
            Expanded(
              child: _Segment(
                mode: m,
                selected: m == mode,
                onTap: () => onChanged(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final WirelessMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final (String label, IconData icon) = WirelessModeBar.describe(mode);

    return Semantics(
      selected: selected,
      button: true,
      child: HoverLift(
        builder: (BuildContext context, bool hovered) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DexRadius.control),
          child: AnimatedContainer(
            duration: DexDuration.micro,
            curve: DexMotion.arrive,
            constraints: const BoxConstraints(minHeight: DexHit.comfortable),
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.md,
              vertical: DexSpace.sm,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? c.signal.withValues(alpha: 0.18)
                  : hovered
                  ? c.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DexRadius.control),
              border: Border.all(
                color: selected ? c.signal : Colors.transparent,
                width: DexStroke.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 15, color: selected ? c.signal : c.muted),
                const SizedBox(width: DexSpace.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelLarge?.copyWith(
                      color: selected ? c.text : c.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Work in flight.
///
/// Held back for [DexDuration.loadingDelay] so a fast command does not flash an
/// indicator, then kept for at least [DexDuration.loadingFloor] so it is
/// readable rather than a blink.
class Working extends StatefulWidget {
  const Working({required this.busy, this.label, super.key});

  final bool busy;
  final String? label;

  @override
  State<Working> createState() => _WorkingState();
}

class _WorkingState extends State<Working> {
  Timer? _delay;
  Timer? _floor;
  bool _visible = false;
  bool _hideWhenFloorEnds = false;

  @override
  void didUpdateWidget(Working oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _start();
    } else if (!widget.busy && oldWidget.busy) {
      _stop();
    }
  }

  void _start() {
    _delay?.cancel();
    _hideWhenFloorEnds = false;
    _delay = Timer(DexDuration.loadingDelay, () {
      if (!mounted) {
        return;
      }
      setState(() => _visible = true);
      _floor = Timer(DexDuration.loadingFloor, () {
        _floor = null;
        if (mounted && _hideWhenFloorEnds) {
          setState(() {
            _visible = false;
            _hideWhenFloorEnds = false;
          });
        }
      });
    });
  }

  void _stop() {
    _delay?.cancel();
    _delay = null;
    if (!_visible) {
      return;
    }
    if (_floor != null) {
      _hideWhenFloorEnds = true;
    } else {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _floor?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    // Reserve the height either way so revealing the indicator never shifts
    // the controls beside it.
    if (!_visible) {
      return const SizedBox(height: DexHit.minimum);
    }
    return Entrance(
      rise: 4,
      child: SizedBox(
        height: DexHit.minimum,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: DexSpace.md,
              height: DexSpace.md,
              child: CircularProgressIndicator(
                strokeWidth: DexStroke.focusRing,
                color: c.signal,
              ),
            ),
            const SizedBox(width: DexSpace.sm),
            Text(
              widget.label ?? 'Talking to the phone…',
              style: t.labelSmall?.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
