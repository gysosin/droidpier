import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../util/app_version.dart';
import '../theme/dex_theme.dart';
import '../util/error_guidance.dart';
import '../motion/dex_motion.dart';
import '../theme/dex_tokens.dart';
import '../widgets/bench_backdrop.dart';
import '../widgets/link_rail.dart';

/// Boot screen.
///
/// Composition is two columns on a wide window: identity and intent on the
/// left, the Link Rail on the right, standing in the phosphor bloom. Below
/// both, a bench readout strip in mono — the machine's own account of the link.
/// Narrow windows stack the same pieces in the same order.
class BootScreen extends StatelessWidget {
  const BootScreen({
    required this.boot,
    required this.onConnect,
    required this.onRetry,
    this.device,
    this.deviceCount = 0,
    super.key,
  });

  final BootState boot;
  final VoidCallback onConnect;
  final VoidCallback onRetry;

  /// The phone the desk is coming up on, once one has been chosen.
  ///
  /// The screen used to be handed the boot state and nothing else, so it could
  /// not name the phone even in principle. With one attached that is merely
  /// incurious; with two it means the app connects to one of them and never
  /// says which.
  final DeviceSummary? device;

  /// How many phones are attached, which decides whether there is a choice to
  /// offer at all. Naming one of two is only half an answer.
  final int deviceCount;

  bool get _isFailed => boot.phase == BootPhase.failed;
  bool get _isIdle => boot.phase == BootPhase.idle;
  bool get _isReady => boot.phase == BootPhase.ready;

  /// The headline is the state, said plainly. The rail carries the detail.
  String get _headline => switch (boot.phase) {
    BootPhase.idle => 'Plug in your phone',
    BootPhase.ready => 'Your desk is ready',
    BootPhase.failed => 'The link did not come up',
    _ => 'Bringing up the link',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BenchBackdrop(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const Entrance(child: _Masthead()),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool wide = constraints.maxWidth >= 820;
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DexSpace.xxxl,
                              vertical: DexSpace.xl,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 900),
                              child: wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: <Widget>[
                                        Expanded(
                                          flex: 5,
                                          child: Entrance(
                                            order: 1,
                                            child: _Intent(screen: this),
                                          ),
                                        ),
                                        const SizedBox(width: DexSpace.xxxl),
                                        Expanded(
                                          flex: 4,
                                          child: Entrance(
                                            order: 3,
                                            rise: 16,
                                            child: _RailPanel(boot: boot),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Entrance(
                                          order: 1,
                                          child: _Intent(screen: this),
                                        ),
                                        const SizedBox(height: DexSpace.xxl),
                                        Entrance(
                                          order: 3,
                                          rise: 16,
                                          child: _RailPanel(boot: boot),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Entrance(order: 5, child: _BenchReadout(boot: boot)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Masthead: the product identity, held at the top edge like an instrument's
/// faceplate label rather than floating with the content.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.xxl,
        vertical: DexSpace.lg,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: c.line, width: DexStroke.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          const DexMark(size: 22),
          const SizedBox(width: DexSpace.md),
          // The reference's faceplate: the product, a slash, and the one word
          // that says what it is for — with only that word carrying signal.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: DexGlass.of(context).fill,
              borderRadius: BorderRadius.circular(DexRadius.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'DROIDPIER',
                  style: DexTheme.data(
                    c,
                    size: 10,
                    color: c.text,
                  ).copyWith(letterSpacing: 1.8, fontWeight: FontWeight.w700),
                ),
                Text(
                  ' / ',
                  style: DexTheme.data(
                    c,
                    size: 10,
                  ).copyWith(letterSpacing: 1.8),
                ),
                Text(
                  'LINK',
                  style: DexTheme.data(
                    c,
                    size: 10,
                    color: c.signal,
                  ).copyWith(letterSpacing: 1.8, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: DexSpace.md),
          Text(versionLabel(), style: DexTheme.data(c, size: 10)),
        ],
      ),
    );
  }
}

class _Intent extends StatelessWidget {
  const _Intent({required this.screen});

  final BootScreen screen;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final BootState boot = screen.boot;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // What this screen is, above what it is currently doing. The headline
        // changes with the phase; this does not, so a person landing here
        // twice recognises where they are before reading anything.
        Text(
          'PHYSICAL DESKTOP RUNTIME',
          style: DexTheme.data(
            c,
            size: 10,
            color: c.signal,
          ).copyWith(letterSpacing: 2, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: DexSpace.md),
        SwapText(screen._headline, style: t.displaySmall!),
        const SizedBox(height: DexSpace.md),
        Text(
          boot.message,
          style: t.bodyLarge?.copyWith(
            color: screen._isFailed ? c.fault : c.muted,
          ),
        ),
        // Which phone, and how it is attached.
        //
        // The name alone is not enough when someone has two of the same model
        // on the desk — the cable is what tells them apart — and the whole
        // complaint this answers is not knowing which one the desk came up on.
        if (screen.device case final DeviceSummary d) ...<Widget>[
          const SizedBox(height: DexSpace.lg),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DexGlass.of(context).fillSubtle,
              borderRadius: BorderRadius.circular(DexRadius.card),
              border: Border.all(
                color: DexGlass.of(context).stroke,
                width: DexStroke.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(DexIcons.portrait, size: 18, color: c.trace),
                const SizedBox(width: DexSpace.md),
                // Flexible, not fixed: the device line carries a name, a
                // transport and an Android version, and a narrow boot column
                // has to be allowed to shorten it rather than run past the
                // card's edge.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'TARGET TRANSPORT NODE',
                        style: DexTheme.data(
                          c,
                          size: 9,
                        ).copyWith(letterSpacing: 1.6),
                      ),
                      const SizedBox(height: 2),
                      _DeviceLine(device: d, colors: c),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (boot.error != null) ...<Widget>[
          const SizedBox(height: DexSpace.lg),
          _ErrorNote(
            error: boot.error!,
            colors: c,
            alreadyStated: boot.message,
          ),
        ],
        const SizedBox(height: DexSpace.xl),
        Row(
          children: <Widget>[
            if (screen._isIdle)
              FilledButton(
                onPressed: screen.onConnect,
                child: const Text('Connect phone'),
              )
            // More than one attached, and the desk picked one. Offer the
            // choice while it still matters — by the time it has failed, which
            // phone it was going to use is beside the point.
            else if (!screen._isFailed && screen.deviceCount > 1) ...<Widget>[
              const _WorkingLabel(),
              const SizedBox(width: DexSpace.lg),
              OutlinedButton(
                onPressed: screen.onConnect,
                child: const Text('Choose a phone'),
              ),
            ] else if (screen._isFailed) ...<Widget>[
              FilledButton(
                onPressed: screen.onRetry,
                child: const Text('Try again'),
              ),
              const SizedBox(width: DexSpace.sm),
              // Retrying is not the answer to every failure. Two phones
              // connected at once is fixed by picking one, and nothing about
              // pressing the same button again gets there.
              OutlinedButton(
                onPressed: screen.onConnect,
                child: const Text('Choose a phone'),
              ),
            ] else if (screen._isReady)
              OutlinedButton(
                onPressed: screen.onConnect,
                child: const Text('Open workspace'),
              )
            else
              const _WorkingLabel(),
          ],
        ),
      ],
    );
  }
}

/// Which phone, and over what.
class _DeviceLine extends StatelessWidget {
  const _DeviceLine({required this.device, required this.colors});

  final DeviceSummary device;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final String how = switch (device.connectionKind) {
      DeviceConnectionKind.usb => 'USB',
      DeviceConnectionKind.wifi => 'Wi-Fi',
    };
    final String label = <String>[
      device.model ?? device.name,
      how,
      if (device.androidVersion case final String v) 'Android $v',
    ].join('  ·  ');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          device.connectionKind == DeviceConnectionKind.usb
              ? DexIcons.usb
              : DexIcons.wifi,
          size: 14,
          color: colors.muted,
        ),
        const SizedBox(width: DexSpace.sm),
        // Shortened rather than run past its container. The model is first in
        // the line because it is what distinguishes two phones of the same
        // name, so it is the part that survives truncation.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DexTheme.data(colors, size: 12),
          ),
        ),
      ],
    );
  }
}

/// Connecting has no button — it has a state. Saying so beats a dead control.
class _WorkingLabel extends StatelessWidget {
  const _WorkingLabel();

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: c.signal),
        ),
        const SizedBox(width: DexSpace.md),
        Text(
          'Working…',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

/// The rail gets its own panel so it reads as an instrument mounted on the
/// bench, not as a list of steps floating in the page.
class _RailPanel extends StatelessWidget {
  const _RailPanel({required this.boot});

  final BootState boot;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DexSpace.xl,
        DexSpace.xl,
        DexSpace.xl,
        DexSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(DexRadius.dialog),
        border: Border.all(color: c.line, width: DexStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'PHYSICAL TRANSPORT RAIL',
                      style: DexTheme.data(
                        c,
                        size: 10,
                        color: c.signal,
                      ).copyWith(letterSpacing: 2, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Five-stage hardware handshake',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: c.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DexSpace.md),
              // The two ports the whole rail is about, stated once at the top
              // rather than only appearing as station labels partway down.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DexSpace.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: DexGlass.of(context).fillSubtle,
                  borderRadius: BorderRadius.circular(DexRadius.pill),
                  border: Border.all(
                    color: DexGlass.of(context).stroke,
                    width: DexStroke.hairline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.trace,
                      ),
                    ),
                    const SizedBox(width: DexSpace.xs),
                    Text('PORT 3698/3699', style: DexTheme.data(c, size: 10)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DexSpace.md),
          Divider(color: c.line, height: DexSpace.xl),
          LinkRail(stages: boot.stages),
        ],
      ),
    );
  }
}

/// Bench readout: the machine's own account, in machine type. Tabular figures
/// mean the numbers do not jitter as they change.
class _BenchReadout extends StatelessWidget {
  const _BenchReadout({required this.boot});

  final BootState boot;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final int done = boot.stages
        .where((BootStage s) => s.status == StageStatus.complete)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.xxl,
        vertical: DexSpace.md,
      ),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(color: c.line, width: DexStroke.hairline),
        ),
      ),
      child: Wrap(
        spacing: DexSpace.xl,
        runSpacing: DexSpace.sm,
        children: <Widget>[
          _Readout(label: 'phase', value: boot.phase.name, colors: c),
          _Readout(
            label: 'stages',
            value: '$done/${boot.stages.length}',
            colors: c,
          ),
          _Readout(label: 'agent', value: 'tcp 3698', colors: c),
          _Readout(label: 'companion', value: 'ws 3699', colors: c),
          _Readout(label: 'adb', value: 'tcp 5037', colors: c),
          // The claim the product makes about itself, on the screen where a
          // person is deciding whether to plug their phone in.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.trace,
                ),
              ),
              const SizedBox(width: DexSpace.sm),
              Text(
                'local only \u00b7 no cloud relay',
                style: DexTheme.data(c, size: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: DexTheme.data(colors, size: 11)),
        const SizedBox(width: DexSpace.sm),
        Text(value, style: DexTheme.data(colors, size: 11, color: colors.text)),
      ],
    );
  }
}

/// Errors state what happened and the next move. They do not apologise.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({
    required this.error,
    required this.colors,
    this.alreadyStated,
  });

  final OpenDexError error;

  /// The line shown above this box, if any. When it says the same thing as
  /// [OpenDexError.message] the box does not repeat it.
  final String? alreadyStated;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DexSpace.md),
      decoration: BoxDecoration(
        color: colors.raised,
        border: Border(
          left: BorderSide(color: colors.fault, width: DexStroke.focusRing),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(DexRadius.card),
          bottomRight: Radius.circular(DexRadius.card),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Only when it adds something. The boot line above already carries
          // this sentence, and printing it twice in two styles reads as a
          // rendering fault rather than emphasis.
          if (error.message.trim() != (alreadyStated ?? '').trim()) ...<Widget>[
            Text(error.message, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: DexSpace.xs),
          ],
          // What to try, before the machine-readable parts. This is the only
          // line most people will read, so it goes above the code and above
          // the transcript rather than after them.
          if (guidanceFor(error) case final String advice) ...<Widget>[
            const SizedBox(height: DexSpace.xs),
            Text(advice, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: DexSpace.sm),
          ],
          Text(error.code.name, style: DexTheme.data(colors, size: 11)),
          // The transcript is offered, never shown.
          //
          // It is built from process and adb exceptions, so it can carry a
          // device serial, a network address or a local path. Rendering it
          // puts all of that on screen by default, for everyone standing
          // behind you. Copying it is a decision the person makes, and the
          // line underneath tells them to look before they pass it on.
          if (error.technicalDetails case final String detail
              when detail.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: DexSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: detail.trim())),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, DexHit.comfortable),
                ),
                icon: const Icon(DexIcons.copy, size: 14),
                label: const Text('Copy technical details'),
              ),
            ),
            const SizedBox(height: DexSpace.xs),
            Text(
              'Technical information about this computer and the phone. '
              'Read it before sharing.',
              style: DexTheme.data(colors, size: 11, color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
