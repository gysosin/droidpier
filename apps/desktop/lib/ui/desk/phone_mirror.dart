import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';

/// The phone, mirrored on the desk.
///
/// Two things are true at once and the widget has to be honest about both: the
/// phone is a *device* whose real state we know (battery, radios, apps), and
/// its *screen* is something we cannot draw until the backend gives us a
/// surface. So this renders the hardware faithfully — frame, status bar,
/// radios, battery, app grid, gesture pill — and says plainly, inside the
/// frame, that the live screen is not available yet. It does not fake a
/// screenshot.
///
/// Docked bottom-right above the taskbar, following the reference.
class PhoneMirror extends StatelessWidget {
  const PhoneMirror({
    required this.snapshot,
    required this.now,
    required this.onClose,
    required this.onLaunch,
    this.width = 240,
    this.overVideo = false,
    super.key,
  });

  final OpenDexSnapshot snapshot;
  final DateTime now;
  final VoidCallback onClose;
  final ValueChanged<AndroidApplication> onLaunch;
  final double width;

  /// True while an app window is streaming beneath this one.
  ///
  /// The mirror is layered above the workspace, so its `BackdropFilter` samples
  /// whatever is behind it — and when that is a 60 fps video texture, the blur
  /// runs on every decoded frame. It drops to a flat fill in that case; over a
  /// static wallpaper it keeps the blur, which is free.
  final bool overVideo;

  /// How tall the mirror renders at [width]. The desk reserves exactly this
  /// much so the widget column can never be covered by it — the two used to
  /// be positioned independently, and the phone sat on top of the widgets.
  static double heightFor(double width) => width * 18.5 / 9 + 14;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);

    return Semantics(
      container: true,
      label: 'Phone mirror',
      child: SizedBox(
        width: width,
        child: GlassPanel(
          // A phone is a rounded slab; the frame radius is the one place the
          // desk's 16 px panel radius would be wrong.
          radius: 36,
          fill: glass.substrate,
          stroke: glass.strokeStrong,
          blurred: !overVideo,
          padding: const EdgeInsets.all(DexSpace.sm),
          child: AspectRatio(
            aspectRatio: 9 / 18.5,
            child: ClipRRect(
              // Deliberately off the DexRadius scale. This corner is not desk
              // chrome, it is the depicted phone's own screen, and the token
              // scale describes panels rather than hardware.
              borderRadius: BorderRadius.circular(30),
              // The phone's screen is always dark, whatever the desk's theme
              // is. Two reasons, and they agree: we are mirroring a device
              // whose wallpaper is not ours to restyle, and the light desk
              // wallpaper is pale enough that the white status text on it was
              // effectively invisible.
              child: Theme(
                data: DexTheme.dark(),
                child: DeskWallpaper(
                  child: Column(
                    children: <Widget>[
                      _StatusBar(
                        telemetry: snapshot.telemetry,
                        now: now,
                        onClose: onClose,
                      ),
                      // No home screen is drawn here. Until the companion
                      // casts, the honest thing to show inside the frame is
                      // that nothing is being shown — not an invented grid
                      // of apps the phone may not have.
                      Expanded(child: _Placeholder(snapshot: snapshot)),
                      const _GesturePill(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.telemetry,
    required this.now,
    required this.onClose,
  });

  final DeviceTelemetry telemetry;
  final DateTime now;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final int? battery = telemetry.batteryPercentage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DexSpace.md,
        DexSpace.sm,
        DexSpace.sm,
        0,
      ),
      child: Row(
        children: <Widget>[
          Text(
            _clock(now),
            style: DexTheme.data(c, size: 10, color: Colors.white),
          ),
          const Spacer(),
          const _PunchHole(),
          const Spacer(),
          if (telemetry.wifiEnabled ?? false)
            const Icon(DexIcons.wifi, size: 11, color: Colors.white),
          if (telemetry.bluetoothEnabled ?? false) ...<Widget>[
            const SizedBox(width: 3),
            const Icon(DexIcons.bluetooth, size: 11, color: Colors.white),
          ],
          const SizedBox(width: 3),
          Icon(
            telemetry.charging ? DexIcons.batteryCharging : DexIcons.battery,
            size: 12,
            // Battery is the one readout that changes meaning with its value,
            // so it is the one that gets a colour.
            color: battery != null && battery <= 15 ? c.fault : c.trace,
          ),
          if (battery != null) ...<Widget>[
            const SizedBox(width: 2),
            Text(
              '$battery%',
              style: DexTheme.data(c, size: 9, color: Colors.white),
            ),
          ],
          const SizedBox(width: DexSpace.xs),
          _CloseDot(onClose: onClose),
        ],
      ),
    );
  }
}

class _PunchHole extends StatelessWidget {
  const _PunchHole();

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Center(
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: c.signal.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _CloseDot extends StatelessWidget {
  const _CloseDot({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Tooltip(
      message: 'Hide the phone',
      child: HoverLift(
        builder: (BuildContext context, bool hovered) => InkWell(
          onTap: onClose,
          borderRadius: BorderRadius.circular(DexRadius.pill),
          // WCAG 2.2 SC 2.5.8: the visible dot is small, the target is not.
          child: SizedBox(
            width: DexHit.minimum,
            height: DexHit.minimum,
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: hovered
                      ? c.fault
                      : Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  DexIcons.close,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GesturePill extends StatelessWidget {
  const _GesturePill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.sm, top: DexSpace.xs),
      child: Container(
        width: 76,
        height: 3,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(DexRadius.pill),
        ),
      ),
    );
  }
}

String _clock(DateTime now) {
  final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
  return '$h:${now.minute.toString().padLeft(2, '0')}';
}

/// What the frame holds before there is a stream to hold.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.snapshot});

  final OpenDexSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final String? name = snapshot.selectedDevice?.name;

    return Padding(
      padding: const EdgeInsets.all(DexSpace.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(color: c.line, width: DexStroke.hairline),
            ),
            child: Icon(DexIcons.portrait, size: 20, color: c.muted),
          ),
          const SizedBox(height: DexSpace.md),
          Text(
            name ?? 'Phone',
            textAlign: TextAlign.center,
            style: t.labelLarge?.copyWith(color: c.text),
          ),
          const SizedBox(height: DexSpace.xs),
          Text(
            'Physical device surface linked via ADB. Screen mirroring handled '
            'in freeform windows.',
            textAlign: TextAlign.center,
            style: DexTheme.data(c, size: 10),
          ),
        ],
      ),
    );
  }
}
