import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import '../util/app_version.dart';
import '../theme/dex_colors.dart';
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
                    Text('Settings', style: t.headlineMedium),
                    const SizedBox(height: DexSpace.xs),
                    Text(
                      'How the desk behaves. Your phone’s own settings stay on '
                      'the phone.',
                      style: t.bodyLarge?.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: DexSpace.xl),
                    _Group(
                      title: 'Appearance',
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
                          title: 'Reduce motion',
                          detail:
                              'Skips the entrance animations. Already on if '
                              'your system asks for reduced motion.',
                          colors: c,
                          value: reduceMotion,
                          onChanged: onReduceMotionChanged,
                        ),
                        const SizedBox(height: DexSpace.lg),
                        _SwitchRow(
                          title: 'Frosted panels',
                          detail:
                              'Blurs the desk behind panels. Turn off for a '
                              'flatter, cheaper desk on weaker hardware.',
                          colors: c,
                          value: glassEnabled,
                          onChanged: onGlassChanged,
                        ),
                        const SizedBox(height: DexSpace.lg),
                        _WallpaperRow(
                          title: 'Wallpaper',
                          detail: 'The desk background.',
                          colors: c,
                          selected: wallpaperIndex,
                          onSelected: onWallpaperChanged,
                        ),
                      ],
                    ),
                    const SizedBox(height: DexSpace.lg),
                    _Group(
                      title: 'Desktop mode',
                      colors: c,
                      onReset: () => onSnapChanged(true),
                      children: <Widget>[
                        _SwitchRow(
                          title: 'Window snapping',
                          detail: 'Halves and quarters at screen edges.',
                          value: snapEnabled,
                          onChanged: onSnapChanged,
                          colors: c,
                        ),
                      ],
                    ),
                    if (onManagePhones != null ||
                        onOpenPermissions != null) ...<Widget>[
                      const SizedBox(height: DexSpace.lg),
                      _Group(
                        title: 'Phone',
                        colors: c,
                        children: <Widget>[
                          if (onManagePhones != null)
                            _ActionRow(
                              title: 'Manage phones',
                              detail: 'Switch phone or pair a new one.',
                              action: 'Open',
                              onPressed: onManagePhones!,
                              colors: c,
                            ),
                          if (onManagePhones != null &&
                              onOpenPermissions != null)
                            Divider(
                              height: 1,
                              thickness: DexStroke.hairline,
                              color: c.line,
                            ),
                          if (onOpenPermissions != null)
                            _ActionRow(
                              title: 'Permissions',
                              detail: 'What the phone has granted the desktop.',
                              action: 'Open',
                              onPressed: onOpenPermissions!,
                              colors: c,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: DexSpace.lg),
                    _Group(
                      title: 'Connection',
                      colors: c,
                      children: <Widget>[
                        _ActionRow(
                          title: 'Disconnect',
                          detail: deviceLabel == null
                              ? 'End the session.'
                              : 'End the session with $deviceLabel. The apps '
                                    'keep running on the phone.',
                          action: 'Disconnect',
                          onPressed: onDisconnect,
                          colors: c,
                          danger: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: DexSpace.lg),
                    _Group(
                      title: 'About',
                      colors: c,
                      children: <Widget>[
                        _NoteRow(
                          title: 'DroidPier',
                          detail: 'Desktop workspace for Android.',
                          mono: versionLabel(),
                          colors: c,
                        ),
                        Divider(
                          height: 1,
                          thickness: DexStroke.hairline,
                          color: c.line,
                        ),
                        _NoteRow(
                          title: 'Licenses',
                          detail:
                              'Original code is Apache-2.0. Bundled components '
                              'keep their own terms: FFmpeg '
                              '(LGPL-2.1-or-later), scrcpy (Apache-2.0), '
                              'bundled fonts (OFL-1.1). Full texts and '
                              'third-party notices ship with the app in',
                          mono: 'resources/licenses',
                          colors: c,
                        ),
                        Divider(
                          height: 1,
                          thickness: DexStroke.hairline,
                          color: c.line,
                        ),
                        _NoteRow(
                          title: 'Scope',
                          detail:
                              'Desktop audio forwarding is not implemented; '
                              'sound stays on the phone. Windows and macOS '
                              'builds are in development.',
                          colors: c,
                        ),
                      ],
                    ),
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
  });

  final String title;
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
                    child: Text(
                      'Reset',
                      style: DexTheme.data(
                        colors,
                        size: 10,
                        color: colors.muted,
                      ).copyWith(letterSpacing: 1.4),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DexSpace.sm),
        Container(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(DexRadius.card),
            border: Border.all(color: colors.line, width: DexStroke.hairline),
          ),
          // Stretch, not the default centre. Every row here is meant to be
          // left-aligned and full width; the wide ones only looked that way by
          // accident, and the first narrow row added — the accent swatches —
          // rendered visibly centred.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
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

/// A row that only states something. No control, because there is nothing here
/// the desk can act on — the same reason the permission buttons were removed.
///
/// [mono] is appended to [detail] as a final span in the data face, for a path
/// or other literal that should not read as prose.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.title,
    required this.detail,
    required this.colors,
    this.mono,
  });

  final String title;
  final String detail;
  final String? mono;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle? body = t.bodyMedium?.copyWith(color: colors.muted);
    return Padding(
      padding: const EdgeInsets.all(DexSpace.md),
      // Expanded, as in _RowShell: a bare Column shrink-wraps and _Group's
      // Column then centres it, which reads as a different surface entirely.
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: t.bodyLarge),
                const SizedBox(height: 2),
                if (mono == null)
                  Text(detail, style: body)
                else
                  Text.rich(
                    TextSpan(
                      style: body,
                      children: <InlineSpan>[
                        TextSpan(text: '$detail '),
                        TextSpan(
                          text: mono,
                          style: DexTheme.data(
                            colors,
                            size: 12,
                            color: colors.text,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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
      trailing: Semantics(
        toggled: value,
        label: title,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.signal,
        ),
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
      trailing: Wrap(
        spacing: DexSpace.xs,
        children: <Widget>[
          for (final MapEntry<ThemeMode, String> e in _labels.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: e.key == value,
              onSelected: (_) => onChanged(e.key),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.detail,
    required this.action,
    required this.onPressed,
    required this.colors,
    this.danger = false,
  });

  final String title;
  final String detail;
  final String action;
  final VoidCallback onPressed;
  final DexColors colors;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      title: title,
      detail: detail,
      colors: colors,
      trailing: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? colors.fault : colors.text,
          side: BorderSide(
            color: danger ? colors.fault : colors.line,
            width: DexStroke.hairline,
          ),
        ),
        child: Text(action),
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
        Wrap(
          spacing: DexSpace.md,
          runSpacing: DexSpace.md,
          children: <Widget>[
            // Index 0 is the theme's own wallpaper; its swatch previews the
            // current theme colours so it reads right in light and dark.
            _Swatch(
              choice: DexWallpaperChoice(
                name: 'Default',
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
      child: Tooltip(
        message: choice.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DexRadius.card),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 76,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DexRadius.card),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: choice.colors,
                  ),
                  border: Border.all(
                    color: selected ? colors.signal : colors.line,
                    width: selected ? 2.5 : DexStroke.hairline,
                  ),
                ),
                child: selected
                    ? Icon(DexIcons.check, color: Colors.white, size: 20)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                choice.name,
                style: t.bodySmall?.copyWith(
                  color: selected ? colors.text : colors.muted,
                ),
              ),
            ],
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
        Wrap(
          spacing: DexSpace.md,
          runSpacing: DexSpace.md,
          children: <Widget>[
            for (int i = 0; i < kAccents.length; i++)
              _AccentSwatch(
                accent: kAccents[i],
                colour: accentFor(i, brightness),
                selected: i == selected || (selected < 0 && i == 0),
                colors: colors,
                onTap: () => onSelected(i),
              ),
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
      child: Tooltip(
        message: accent.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DexRadius.pill),
          child: Container(
            width: DexHit.comfortable,
            height: DexHit.comfortable,
            decoration: BoxDecoration(
              color: colour,
              shape: BoxShape.circle,
              // Selection out-contrasts hover, which out-contrasts rest.
              border: Border.all(
                color: selected ? colors.text : colors.line,
                width: selected ? DexStroke.focusRing : DexStroke.hairline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
