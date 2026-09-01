import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../apps/app_glyph.dart';
import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';
import '../util/app_display_name.dart';

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
    this.width = 208,
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
          radius: 30,
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
              borderRadius: BorderRadius.circular(24),
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
                      Expanded(
                        child: _Screen(
                          snapshot: snapshot,
                          now: now,
                          onLaunch: onLaunch,
                          overVideo: overVideo,
                        ),
                      ),
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
            const Icon(Icons.wifi, size: 11, color: Colors.white),
          if (telemetry.bluetoothEnabled ?? false) ...<Widget>[
            const SizedBox(width: 3),
            const Icon(Icons.bluetooth, size: 11, color: Colors.white),
          ],
          const SizedBox(width: 3),
          Icon(
            telemetry.charging
                ? Icons.battery_charging_full
                : Icons.battery_std,
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
                child: const Icon(Icons.close, size: 10, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.snapshot,
    required this.now,
    required this.onLaunch,
    required this.overVideo,
  });

  final OpenDexSnapshot snapshot;
  final DateTime now;
  final ValueChanged<AndroidApplication> onLaunch;
  final bool overVideo;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final List<AndroidApplication> apps = snapshot.applications
        .where((AndroidApplication a) => !a.isSystemApp)
        .take(8)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DexSpace.md),
      child: Column(
        children: <Widget>[
          const SizedBox(height: DexSpace.md),
          Text(
            _clock(now),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: 26,
              color: Colors.white,
              fontWeight: FontWeight.w300,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _longDate(now),
            style: DexTheme.data(
              c,
              size: 9,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: DexSpace.md),
          Expanded(
            child: apps.isEmpty
                ? const _NoApps()
                : Center(
                    child: GridView.count(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: DexSpace.sm,
                      crossAxisSpacing: DexSpace.sm,
                      childAspectRatio: 0.78,
                      children: <Widget>[
                        for (final AndroidApplication app in apps)
                          _MiniApp(app: app, onLaunch: () => onLaunch(app)),
                      ],
                    ),
                  ),
          ),
          if (apps.isNotEmpty) ...<Widget>[
            _Dock(apps: apps, onLaunch: onLaunch, overVideo: overVideo),
            const SizedBox(height: DexSpace.sm),
          ],
        ],
      ),
    );
  }
}

/// The phone's dock. The reference keeps four apps pinned across the bottom,
/// which is also what stops the lower half of the screen reading as empty.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.apps,
    required this.onLaunch,
    required this.overVideo,
  });

  final List<AndroidApplication> apps;
  final ValueChanged<AndroidApplication> onLaunch;
  final bool overVideo;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    final List<AndroidApplication> docked = apps.take(4).toList();

    return GlassPanel(
      radius: DexRadius.dialog,
      fill: glass.fillStrong,
      shadow: false,
      // Inside the mirror, so it inherits the same reasoning.
      blurred: !overVideo,
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.sm,
        vertical: DexSpace.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          for (final AndroidApplication app in docked)
            _DockIcon(app: app, onLaunch: () => onLaunch(app)),
        ],
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({required this.app, required this.onLaunch});

  final AndroidApplication app;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final String shown = isPlaceholderLabel(app.label, app.packageName)
        ? displayNameFor(app.packageName)
        : app.label;
    return Semantics(
      button: true,
      label: 'Open $shown',
      child: Tooltip(
        message: shown,
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onLaunch,
            borderRadius: BorderRadius.circular(DexRadius.control),
            child: AnimatedScale(
              duration: DexDuration.micro,
              curve: DexMotion.arrive,
              scale: hovered ? 1.12 : 1,
              child: AppGlyph(app: app, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniApp extends StatelessWidget {
  const _MiniApp({required this.app, required this.onLaunch});

  final AndroidApplication app;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final String shown = isPlaceholderLabel(app.label, app.packageName)
        ? displayNameFor(app.packageName)
        : app.label;
    return Semantics(
      button: true,
      label: 'Open $shown',
      child: Tooltip(
        message: shown,
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onLaunch,
            borderRadius: BorderRadius.circular(DexRadius.control),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedScale(
                  duration: DexDuration.micro,
                  curve: DexMotion.arrive,
                  scale: hovered ? 1.08 : 1,
                  child: AppGlyph(app: app, size: 30),
                ),
                const SizedBox(height: 3),
                Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 7.5,
                    color: Colors.white.withValues(alpha: 0.9),
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

/// Empty state. An empty screen is an invitation to act, not a blank.
class _NoApps extends StatelessWidget {
  const _NoApps();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DexSpace.md),
        child: Text(
          'Apps appear here once the phone finishes connecting.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            height: 1.5,
            color: Colors.white.withValues(alpha: 0.7),
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

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _days = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _longDate(DateTime now) =>
    '${_days[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
