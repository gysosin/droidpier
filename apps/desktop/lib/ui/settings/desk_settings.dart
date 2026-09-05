import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';
import '../widgets/segmented.dart';

import '../util/app_version.dart';
import '../theme/dex_colors.dart';
import '../widgets/toggle.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/dex_accent.dart';
import '../theme/wallpapers.dart';
import '../widgets/bench_backdrop.dart';

/// Settings for the desk itself.
///
/// Modelled on the reference's Settings surface, which groups display options
/// and desktop-mode behaviour. Only the rows this UI can genuinely act on are
/// present: a switch that does nothing when flipped is worse than an absent
/// one, and this project has already shipped that mistake once with the
/// permission buttons.
///
/// The settings still missing — resolution, brightness, keep-phone-screen-on,
/// phone-as-second-surface — need backend commands and an external-display
/// concept that `OpenDexFacade` does not have. They wait on the facade rather
/// than being mocked up here; see `docs/ARCHITECTURE.md`.
class DeskSettings extends StatelessWidget {
  const DeskSettings({
    required this.snapEnabled,
    required this.onSnapChanged,
    required this.themeMode,
    required this.onThemeChanged,
    required this.wallpaperIndex,
    required this.onWallpaperChanged,
    this.accentIndex = 0,
    this.onAccentChanged = _ignoreAccent,
    this.glassEnabled = true,
    this.onGlassChanged = _ignoreGlass,
    this.reduceMotion = false,
    this.onReduceMotionChanged = _ignoreGlass,
    required this.onDisconnect,
    this.onOpenPermissions,
    this.onManagePhones,
    this.deviceLabel,
    super.key,
  });

  final bool snapEnabled;
  final ValueChanged<bool> onSnapChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final int wallpaperIndex;
  final ValueChanged<int> onWallpaperChanged;

  /// Which accent tints links, focus rings and selected rows. 0 is the
  /// product's own blue.
  final int accentIndex;
  final ValueChanged<int> onAccentChanged;

  /// Whether panels frost what is behind them, and its setter.
  final bool glassEnabled;
  final ValueChanged<bool> onGlassChanged;

  /// Whether to cut motion beyond the platform setting, and its setter.
  final bool reduceMotion;
  final ValueChanged<bool> onReduceMotionChanged;

  static void _ignoreAccent(int _) {}
  static void _ignoreGlass(bool _) {}
  final VoidCallback onDisconnect;

  /// The tray no longer carries these; Settings is the hub. Null hides the row
  /// (e.g. in the golden harness).
  final VoidCallback? onOpenPermissions;
  final VoidCallback? onManagePhones;
  final String? deviceLabel;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BenchBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DexSpace.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: DexHit.comfortable,
                          height: DexHit.comfortable,
                          decoration: BoxDecoration(
                            color: DexGlass.of(context).fill,
                            borderRadius: BorderRadius.circular(
                              DexRadius.control,
                            ),
                          ),
                          child: Icon(
                            DexIcons.monitor,
                            size: 18,
                            color: c.signal,
                          ),
                        ),
                        const SizedBox(width: DexSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('Desk Settings', style: t.titleLarge),
                              Text(
                                'How the desk behaves. Your phone’s own '
                                'settings stay on the phone.',
                                style: t.bodySmall?.copyWith(color: c.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DexSpace.xl),
                    _Group(
                      title: 'Appearance',
                      icon: DexIcons.palette,
                      colors: c,
                      onReset: () {
                        onThemeChanged(ThemeMode.system);
                        onAccentChanged(0);
                        onWallpaperChanged(0);
                        onGlassChanged(true);
                        onReduceMotionChanged(false);
                      },
                      children: <Widget>[
                        _ChoiceRow(
                          title: 'Theme',
                          detail: 'Dark reduces glare on external panels.',
                          colors: c,
                          value: themeMode,
                          onChanged: onThemeChanged,
                        ),
                        const SizedBox(height: DexSpace.md),
                        _AccentRow(
                          selected: accentIndex,
                          onSelected: onAccentChanged,
                          colors: c,
                        ),
                        const SizedBox(height: DexSpace.lg),
                        _SwitchRow(
                          title: 'Frosted Panels',
                          detail:
                              'Blurs the desk behind panels. Turn off for a '
                              'flatter, cheaper desk on weaker hardware.',
                          colors: c,
                          value: glassEnabled,
                          onChanged: onGlassChanged,
                        ),
                        const SizedBox(height: DexSpace.lg),
                        _SwitchRow(
                          title: 'Reduce Motion',
                          detail:
                              'Skips the entrance animations. Already on if '
                              'your system asks for reduced motion.',
                          colors: c,
                          value: reduceMotion,
                          onChanged: onReduceMotionChanged,
                        ),
                        const SizedBox(height: DexSpace.lg),
                        _WallpaperRow(
                          title: 'Lit Desktop Wallpaper',
                          detail: 'The desk background.',
                          colors: c,
                          selected: wallpaperIndex,
                          onSelected: onWallpaperChanged,
                        ),
                      ],
                    ),
                    const SizedBox(height: DexSpace.lg),
                    _Group(
                      title: 'Desktop Mode',
                      colors: c,
                      onReset: () => onSnapChanged(true),
                      children: <Widget>[
                        _SwitchRow(
                          title: 'Window Snapping',
                          detail: 'Halves and quarters at screen edges.',
                          value: snapEnabled,
                          onChanged: onSnapChanged,
                          colors: c,
                        ),
                      ],
                    ),
                    const SizedBox(height: DexSpace.lg),
                    _Group(
                      title: 'Phone links',
                      icon: DexIcons.smartphone,
                      colors: c,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(DexSpace.sm),
                          // Bounded on purpose: stretch needs a height to
                          // stretch to, and the settings column scrolls.
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                if (onManagePhones != null) ...<Widget>[
                                  Expanded(
                                    child: _LinkTile(
                                      title: 'Manage Phones…',
                                      detail: 'Switch phone or pair Wi-Fi',
                                      onPressed: onManagePhones!,
                                      colors: c,
                                    ),
                                  ),
                                  const SizedBox(width: DexSpace.sm),
                                ],
                                if (onOpenPermissions != null) ...<Widget>[
                                  Expanded(
                                    child: _LinkTile(
                                      title: 'Permissions…',
                                      detail:
                                          'What the phone has granted the desk',
                                      onPressed: onOpenPermissions!,
                                      colors: c,
                                    ),
                                  ),
                                  const SizedBox(width: DexSpace.sm),
                                ],
                                Expanded(
                                  child: _LinkTile(
                                    title: 'Disconnect',
                                    detail: deviceLabel == null
                                        ? 'End active session'
                                        : 'End the session with $deviceLabel',
                                    onPressed: onDisconnect,
                                    colors: c,
                                    danger: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DexSpace.lg),
                    _AboutCard(colors: c),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    required this.colors,
    this.onReset,
    this.icon,
  });

  final String title;

  /// The group's glyph, where the reference gives it one.
  final IconData? icon;
  final List<Widget> children;
  final DexColors colors;

  /// Restores this section's defaults. Null for sections that hold no
  /// preferences — Connection and About — because a reset there would do
  /// nothing, and a control that does nothing is worse than no control.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon case final IconData glyph) ...<Widget>[
              Icon(glyph, size: 12, color: colors.signal),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: DexTheme.data(
                  colors,
                  size: 10,
                  color: colors.muted,
                ).copyWith(letterSpacing: 1.4),
              ),
            ),
            if (onReset case final VoidCallback reset)
              Tooltip(
                message: 'Reset $title',
                child: InkWell(
                  onTap: reset,
                  borderRadius: BorderRadius.circular(DexRadius.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DexSpace.sm,
                      vertical: DexSpace.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(DexIcons.rotateCcw, size: 11, color: colors.muted),
                        const SizedBox(width: DexSpace.xs),
                        Text(
                          'Reset group',
                          style: DexTheme.data(
                            colors,
                            size: 10,
                            color: colors.muted,
                          ).copyWith(letterSpacing: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DexSpace.sm),
        // Stretch, not the default centre: every row is left-aligned and full
        // width, and the narrow ones — the accent cards — once rendered
        // centred by accident.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.title,
    required this.detail,
    required this.trailing,
    required this.colors,
  });

  final String title;
  final String detail;
  final Widget trailing;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(DexSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: t.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: t.bodyMedium?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: DexSpace.md),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      title: title,
      detail: detail,
      colors: colors,
      trailing: DexToggle(
        value: value,
        onChanged: onChanged,
        semanticLabel: title,
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  final String title;
  final String detail;
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;
  final DexColors colors;

  static const Map<ThemeMode, String> _labels = <ThemeMode, String>{
    ThemeMode.system: 'System',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      title: title,
      detail: detail,
      colors: colors,
      // DexSegmented, not ChoiceChip. Material resolves a selected chip's fill
      // from `secondaryContainer`, which lands on emerald here — so choosing a
      // theme lit up in the colour this design reserves for telemetry.
      trailing: DexSegmented(
        options: _labels.values.toList(),
        selected: _labels.keys.toList().indexOf(value),
        colors: colors,
        onSelect: (int i) => onChanged(_labels.keys.elementAt(i)),
      ),
    );
  }
}

/// A row of wallpaper swatches; the selected one carries a ring.
class _WallpaperRow extends StatelessWidget {
  const _WallpaperRow({
    required this.title,
    required this.detail,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String detail;
  final DexColors colors;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: t.titleSmall),
        const SizedBox(height: 2),
        Text(detail, style: t.bodySmall?.copyWith(color: colors.muted)),
        const SizedBox(height: DexSpace.md),
        _FourUp(
          children: <Widget>[
            // Index 0 is the theme's own wallpaper; its swatch previews the
            // current theme colours so it reads right in light and dark.
            _Swatch(
              choice: DexWallpaperChoice(
                name: 'Default Lit',
                colors: DexGlass.of(context).wallpaper,
              ),
              selected: selected <= 0,
              colors: colors,
              onTap: () => onSelected(0),
            ),
            for (int i = 0; i < kWallpaperChoices.length; i++)
              _Swatch(
                choice: kWallpaperChoices[i],
                selected: i + 1 == selected,
                colors: colors,
                onTap: () => onSelected(i + 1),
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final DexWallpaperChoice choice;
  final bool selected;
  final DexColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${choice.name} wallpaper',
      excludeSemantics: true,
      child: Tooltip(
        message: choice.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DexRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.md,
              vertical: DexSpace.sm,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.signal.withValues(alpha: 0.12)
                  : colors.surface.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(DexRadius.card),
              border: Border.all(
                color: selected ? colors.signal : colors.line,
                width: selected ? DexStroke.focusRing : DexStroke.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: choice.colors,
                    ),
                  ),
                ),
                const SizedBox(width: DexSpace.sm),
                Flexible(
                  child: Text(
                    choice.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: selected ? colors.text : colors.muted,
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

/// A row of accent swatches; the selected one carries a ring.
///
/// Each swatch previews the value for the theme currently on screen, so the
/// light-mode swatches show their darker light-mode colours rather than the
/// dark-mode ones that would be unreadable there.
class _AccentRow extends StatelessWidget {
  const _AccentRow({
    required this.selected,
    required this.onSelected,
    required this.colors,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Accent', style: t.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Tints links, focus rings and the selected row.',
          style: t.bodySmall?.copyWith(color: colors.muted),
        ),
        const SizedBox(height: DexSpace.md),
        Row(
          children: <Widget>[
            for (int i = 0; i < kAccents.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: DexSpace.sm),
              Expanded(
                child: _AccentSwatch(
                  accent: kAccents[i],
                  colour: accentFor(i, brightness),
                  selected: i == selected || (selected < 0 && i == 0),
                  colors: colors,
                  onTap: () => onSelected(i),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.colour,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final DexAccent accent;
  final Color colour;
  final bool selected;
  final DexColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: accent.name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DexRadius.card),
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? colour.withValues(alpha: 0.12)
                  : colors.surface.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(DexRadius.card),
              border: Border.all(
                color: selected ? colour : colors.line,
                width: DexStroke.hairline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DexSpace.sm,
                vertical: DexSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // The swatch itself wears the ring: it is what the eye
                  // compares across the row, and what the picker's tests read.
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colour,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? colors.text : colors.line,
                        width: selected
                            ? DexStroke.focusRing
                            : DexStroke.hairline,
                      ),
                    ),
                    child: selected
                        ? Icon(DexIcons.check, size: 14, color: colors.bg)
                        : null,
                  ),
                  const SizedBox(height: 6),
                  // The name under the swatch, as the reference sets it: a
                  // colour is not a label.
                  Text(
                    accent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? colors.text : colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three phone links: a title, what it does, and nothing else. The
/// destructive one is set in the fault colour rather than given a second
/// confirmation, because it ends a session, not data.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.title,
    required this.detail,
    required this.onPressed,
    required this.colors,
    this.danger = false,
  });

  final String title;
  final String detail;
  final VoidCallback onPressed;
  final DexColors colors;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DexRadius.card),
        child: Container(
          padding: const EdgeInsets.all(DexSpace.md),
          constraints: const BoxConstraints(minHeight: DexHit.primary),
          decoration: BoxDecoration(
            color: danger
                ? colors.fault.withValues(alpha: 0.10)
                : colors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(DexRadius.card),
            border: Border.all(
              color: danger ? colors.fault.withValues(alpha: 0.4) : colors.line,
              width: DexStroke.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(
                  color: danger ? colors.fault : colors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four to a row, however many there are: the reference's wallpaper grid.
class _FourUp extends StatelessWidget {
  const _FourUp({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i += 4) {
      final List<Widget> cells = <Widget>[];
      for (int j = 0; j < 4; j++) {
        if (j > 0) cells.add(const SizedBox(width: DexSpace.sm));
        cells.add(
          Expanded(
            child: i + j < children.length
                ? children[i + j]
                : const SizedBox.shrink(),
          ),
        );
      }
      if (i > 0) rows.add(const SizedBox(height: DexSpace.sm));
      rows.add(Row(children: cells));
    }
    return Column(children: rows);
  }
}

/// About, as the reference sets it: one mono card with the name, the build,
/// the licence in a sentence, and the audio limitation in amber.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Container(
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: glass.fillSubtle,
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: glass.stroke, width: DexStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'DroidPier Desktop',
                  style: DexTheme.data(
                    colors,
                    size: 11,
                    color: colors.text,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                versionLabel(),
                style: DexTheme.data(
                  colors,
                  size: 11,
                  color: colors.signal,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: DexSpace.sm),
          Text(
            'Your Android. A bigger workspace. Apache-2.0 open source licence. '
            'Bundled components keep their own licences \u2014 FFmpeg '
            '(LGPL-2.1-or-later), scrcpy (Apache-2.0), the fonts (OFL-1.1); '
            'full texts and notices ship in resources/licenses.',
            style: DexTheme.data(colors, size: 11),
          ),
          const SizedBox(height: DexSpace.sm),
          Container(
            padding: const EdgeInsets.all(DexSpace.sm),
            decoration: BoxDecoration(
              color: colors.warn.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DexRadius.control),
              border: Border.all(
                color: colors.warn.withValues(alpha: 0.20),
                width: DexStroke.hairline,
              ),
            ),
            child: Text(
              'Known limitation: desktop audio forwarding is not implemented; '
              'audio output continues through the physical phone.',
              style: DexTheme.data(colors, size: 10, color: colors.warn),
            ),
          ),
        ],
      ),
    );
  }
}
