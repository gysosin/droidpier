import 'package:flutter/material.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_accent.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_icons.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';
import '../widgets/segmented.dart';
import '../theme/wallpapers.dart';

/// Every design token, rendered from the tokens themselves.
///
/// This is the one surface whose job is to be wrong when something else is.
/// It reads `DexColors`, `DexGlass`, `kAccents`, `kWallpaperChoices` and the
/// primitives directly rather than restating them, so a value that drifts
/// shows up here as a swatch that no longer matches its neighbours — which is
/// how several of the radii that made edges read as unfinished were found.
///
/// Nothing here animates and nothing here is interactive beyond switching
/// what is on display: a specimen sheet that moves is not a specimen sheet.
class TokenSheet extends StatefulWidget {
  const TokenSheet({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<TokenSheet> createState() => _TokenSheetState();
}

enum _Tab { colour, type, components, geometry }

class _TokenSheetState extends State<TokenSheet> {
  _Tab _tab = _Tab.colour;

  /// Whether the specimens below are drawn with their blur.
  ///
  /// Independent of the desk's own setting: the point is to see both, and to
  /// see them beside each other, which is the only way to judge whether the
  /// matte fallback still reads as the same product.
  bool _glass = true;
  // The sheet renders both palettes on demand, whatever the desk is set to:
  // the point of the explorer is to see the token in the mode you are not in.
  bool _dark = true;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _dark ? DexTheme.dark() : DexTheme.light(),
      child: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    return GlassBlurScope(
      enabled: _glass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: DexHit.comfortable,
                height: DexHit.comfortable,
                decoration: BoxDecoration(
                  color: DexGlass.of(context).fill,
                  borderRadius: BorderRadius.circular(DexRadius.control),
                ),
                child: Icon(DexIcons.palette, size: 18, color: c.signal),
              ),
              const SizedBox(width: DexSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Design System Explorer', style: t.titleLarge),
                    Text(
                      'Every token, in both modes and both finishes',
                      style: t.bodySmall?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              DexSegmented(
                options: const <String>['Dark', 'Light'],
                selected: _dark ? 0 : 1,
                colors: c,
                onSelect: (int i) => setState(() => _dark = i == 0),
              ),
              const SizedBox(width: DexSpace.sm),
              DexSegmented(
                options: const <String>['Glass', 'Matte'],
                selected: _glass ? 0 : 1,
                colors: c,
                onSelect: (int i) => setState(() => _glass = i == 0),
              ),
              const SizedBox(width: DexSpace.md),
              Text('Esc to close', style: DexTheme.data(c, size: 10)),
            ],
          ),
          const SizedBox(height: DexSpace.lg),
          _TabStrip(
            labels: const <String>['Colour', 'Type', 'Components', 'Geometry'],
            selected: _Tab.values.indexOf(_tab),
            colors: c,
            onSelect: (int i) => setState(() => _tab = _Tab.values[i]),
          ),
          const SizedBox(height: DexSpace.lg),
          Expanded(
            child: SingleChildScrollView(
              child: switch (_tab) {
                _Tab.colour => _Colour(colors: c),
                _Tab.type => _Type(colors: c),
                _Tab.components => _Components(colors: c),
                _Tab.geometry => _Geometry(colors: c),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The semantic roles, the accents, and the wallpapers.
class _Colour extends StatelessWidget {
  const _Colour({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Heading('Semantic roles', colors: colors),
        _Note(
          'Signal is link state and the primary action. Trace is telemetry. '
          'Neither is ever decoration.',
          colors: colors,
        ),
        Wrap(
          spacing: DexSpace.sm,
          runSpacing: DexSpace.sm,
          children: <Widget>[
            for (final (String name, Color Function(DexColors) pick) in _roles)
              _RoleCard(
                name: name,
                dark: pick(DexColors.dark),
                light: pick(DexColors.light),
                colors: colors,
              ),
          ],
        ),
        _Heading('Glass', colors: colors),
        _Note(
          'Alphas over the wallpaper, not opaque roles. Blur '
          '${glass.blur.round()}.',
          colors: colors,
        ),
        Wrap(
          spacing: DexSpace.sm,
          runSpacing: DexSpace.sm,
          children: <Widget>[
            _Swatch('fill', glass.fill, colors),
            _Swatch('fillStrong', glass.fillStrong, colors),
            _Swatch('fillSubtle', glass.fillSubtle, colors),
            _Swatch('substrate', glass.substrate, colors),
            _Swatch('stroke', glass.stroke, colors),
            _Swatch('strokeStrong', glass.strokeStrong, colors),
          ],
        ),
        _Heading('Accents', colors: colors),
        _Note(
          'Each holds 3:1 against the background it appears on, in both '
          'themes. Every accent darkens for light.',
          colors: colors,
        ),
        Wrap(
          spacing: DexSpace.sm,
          runSpacing: DexSpace.sm,
          children: <Widget>[
            for (final DexAccent a in kAccents)
              _Swatch(
                a.name,
                Theme.of(context).brightness == Brightness.dark
                    ? a.dark
                    : a.light,
                colors,
              ),
          ],
        ),
        _Heading('Wallpapers', colors: colors),
        Wrap(
          spacing: DexSpace.sm,
          runSpacing: DexSpace.sm,
          children: <Widget>[
            for (final DexWallpaperChoice w in kWallpaperChoices)
              _Gradient(name: w.name, colors: w.colors, text: colors),
          ],
        ),
      ],
    );
  }
}

/// Three faces, three jobs.
class _Type extends StatelessWidget {
  const _Type({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Heading('Display — ${DexType.display}', colors: colors),
        Text('Bringing up the link', style: t.headlineMedium),
        _Note('Screen titles, boot stages, empty-state headlines.', colors: colors),
        _Heading('Body — ${DexType.body}', colors: colors),
        Text(
          'All prose, labels, buttons and menus. Deliberately not Inter.',
          style: t.bodyLarge,
        ),
        _Heading('Data — ${DexType.data}', colors: colors),
        _Note(
          'Serials, ports, latency, frame rates, adb output. Tabular figures '
          'are mandatory: these change constantly and must not jitter.',
          colors: colors,
        ),
        Text(
          'RTT 14 ms  ·  TX 4.8 MB/s  ·  RATE 42/s  ·  PORT 3698/3699',
          style: DexTheme.data(colors, size: 13, color: colors.trace),
        ),
        _Heading('Scale', colors: colors),
        for (final (String name, TextStyle? style) in <(String, TextStyle?)>[
          ('displaySmall', t.displaySmall),
          ('headlineMedium', t.headlineMedium),
          ('titleLarge', t.titleLarge),
          ('titleMedium', t.titleMedium),
          ('bodyLarge', t.bodyLarge),
          ('bodyMedium', t.bodyMedium),
          ('labelLarge', t.labelLarge),
          ('labelSmall', t.labelSmall),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: DexSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                SizedBox(
                  width: 130,
                  child: Text(name, style: DexTheme.data(colors, size: 11)),
                ),
                Expanded(child: Text('The quick brown fox', style: style)),
                Text(
                  '${style?.fontSize?.round()}',
                  style: DexTheme.data(colors, size: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Glass beside matte, and the controls that sit on both.
class _Components extends StatelessWidget {
  const _Components({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Heading('Panels', colors: colors),
        _Note(
          'Matte is not a degraded fallback. It is what every panel becomes '
          'while a window streams, and at these alphas the two should be hard '
          'to tell apart.',
          colors: colors,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: GlassBlurScope(
                enabled: true,
                child: _PanelSpecimen(label: 'Glass', colors: colors),
              ),
            ),
            const SizedBox(width: DexSpace.md),
            Expanded(
              child: GlassBlurScope(
                enabled: false,
                child: _PanelSpecimen(
                  label: 'Matte — stream safe',
                  colors: colors,
                ),
              ),
            ),
          ],
        ),
        _Heading('Status', colors: colors),
        Wrap(
          spacing: DexSpace.md,
          runSpacing: DexSpace.sm,
          children: <Widget>[
            _Dot('live', colors.trace, colors),
            _Dot('connecting', colors.signal, colors),
            _Dot('degraded', colors.warn, colors),
            _Dot('failed', colors.fault, colors),
          ],
        ),
      ],
    );
  }
}

/// Hit targets and the radius scale, at size.
class _Geometry extends StatelessWidget {
  const _Geometry({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Heading('Hit targets', colors: colors),
        _Note(
          'WCAG 2.2 SC 2.5.8, which is 24. This is a pointer-driven desktop '
          "application, so Android's 48dp touch guideline does not apply.",
          colors: colors,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            _Box('minimum ${DexHit.minimum.round()}', DexHit.minimum,
                colors.signal, colors),
            const SizedBox(width: DexSpace.md),
            _Box('comfortable ${DexHit.comfortable.round()}',
                DexHit.comfortable, colors.trace, colors),
            const SizedBox(width: DexSpace.md),
            _Box('primary ${DexHit.primary.round()}', DexHit.primary,
                colors.warn, colors),
          ],
        ),
        _Heading('Radii', colors: colors),
        _Note(
          'Four steps and no others. Every corner in the product lands on one '
          'of them; the ones that were a pixel or two off are what made edges '
          'read as unfinished.',
          colors: colors,
        ),
        Row(
          children: <Widget>[
            _Corner('control', DexRadius.control, colors),
            const SizedBox(width: DexSpace.md),
            _Corner('card', DexRadius.card, colors),
            const SizedBox(width: DexSpace.md),
            _Corner('panel', DexRadius.panel, colors),
            const SizedBox(width: DexSpace.md),
            _Corner('pill', DexRadius.pill, colors),
          ],
        ),
        _Heading('Spacing', colors: colors),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final (String n, double v) in <(String, double)>[
              ('xs', DexSpace.xs),
              ('sm', DexSpace.sm),
              ('md', DexSpace.md),
              ('lg', DexSpace.lg),
              ('xl', DexSpace.xl),
              ('xxl', DexSpace.xxl),
              ('xxxl', DexSpace.xxxl),
            ])
              Padding(
                padding: const EdgeInsets.only(right: DexSpace.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(width: v, height: v, color: colors.signal),
                    const SizedBox(height: DexSpace.xs),
                    Text(
                      '$n ${v.round()}',
                      style: DexTheme.data(colors, size: 10),
                    ),
                  ],
                ),
              ),
          ],
        ),
        _Heading('Motion', colors: colors),
        _Note(
          'Transform and opacity only, never layout. Reduced motion is '
          'currently ${DexMotion.enabled(context) ? 'off' : 'on'}.',
          colors: colors,
        ),
        for (final (String n, Duration d) in <(String, Duration)>[
          ('micro', DexDuration.micro),
          ('standard', DexDuration.standard),
          ('enter', DexDuration.enter),
          ('loadingDelay', DexDuration.loadingDelay),
          ('loadingFloor', DexDuration.loadingFloor),
        ])
          Text(
            '$n  ${d.inMilliseconds} ms',
            style: DexTheme.data(colors, size: 11),
          ),
      ],
    );
  }
}

class _PanelSpecimen extends StatelessWidget {
  const _PanelSpecimen({required this.label, required this.colors});

  final String label;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: DexRadius.panel,
      padding: const EdgeInsets.all(DexSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: DexSpace.sm),
          Text(
            'Same geometry, same hairline.',
            style: DexTheme.data(colors, size: 11),
          ),
          const SizedBox(height: DexSpace.md),
          Row(
            children: <Widget>[
              FilledButton(onPressed: () {}, child: const Text('Primary')),
              const SizedBox(width: DexSpace.sm),
              OutlinedButton(onPressed: () {}, child: const Text('Ghost')),
            ],
          ),
        ],
      ),
    );
  }
}


class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.colour, this.colors);

  final String name;
  final Color colour;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    // The hex is on the swatch. A specimen sheet that shows a colour without
    // naming it cannot be used to check anything.
    final String hex = '#${(colour.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase()}';
    final int alpha = (colour.a * 255).round();
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(DexRadius.control),
              border: Border.all(color: colors.line, width: DexStroke.hairline),
            ),
          ),
          const SizedBox(height: DexSpace.xs),
          Text(name, style: Theme.of(context).textTheme.labelSmall),
          Text(
            alpha == 255 ? hex : '$hex · ${(alpha / 255 * 100).round()}%',
            style: DexTheme.data(colors, size: 10),
          ),
        ],
      ),
    );
  }
}

class _Gradient extends StatelessWidget {
  const _Gradient({
    required this.name,
    required this.colors,
    required this.text,
  });

  final String name;
  final List<Color> colors;
  final DexColors text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(DexRadius.control),
            ),
          ),
          const SizedBox(height: DexSpace.xs),
          Text(name, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box(this.label, this.size, this.colour, this.colors);

  final String label;
  final double size;
  final Color colour;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(DexRadius.control),
          ),
        ),
        const SizedBox(height: DexSpace.xs),
        Text(label, style: DexTheme.data(colors, size: 10)),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner(this.label, this.radius, this.colors);

  final String label;
  final double radius;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.line, width: DexStroke.hairline),
          ),
        ),
        const SizedBox(height: DexSpace.xs),
        Text(
          '$label ${radius >= 999 ? 'round' : radius.round()}',
          style: DexTheme.data(colors, size: 10),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.label, this.colour, this.colors);

  final String label;
  final Color colour;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
        ),
        const SizedBox(width: DexSpace.sm),
        Text(label, style: DexTheme.data(colors, size: 11)),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.colors});

  final String text;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DexSpace.xl, bottom: DexSpace.sm),
      child: Text(
        text.toUpperCase(),
        style: DexTheme.data(
          colors,
          size: 10,
          color: colors.signal,
        ).copyWith(letterSpacing: 2),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.colors});

  final String text;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.muted,
        ),
      ),
    );
  }
}

/// Every semantic role, by name, so the card can show both palettes' values.
const List<(String, Color Function(DexColors))> _roles =
    <(String, Color Function(DexColors))>[
      ('bg', _bg),
      ('surface', _surface),
      ('raised', _raised),
      ('line', _line),
      ('text', _text),
      ('muted', _muted),
      ('signal', _signal),
      ('trace', _trace),
      ('warn', _warn),
      ('fault', _fault),
    ];

Color _bg(DexColors c) => c.bg;
Color _surface(DexColors c) => c.surface;
Color _raised(DexColors c) => c.raised;
Color _line(DexColors c) => c.line;
Color _text(DexColors c) => c.text;
Color _muted(DexColors c) => c.muted;
Color _signal(DexColors c) => c.signal;
Color _trace(DexColors c) => c.trace;
Color _warn(DexColors c) => c.warn;
Color _fault(DexColors c) => c.fault;

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// One role, both values: the dark hex over the light hex, each on its own
/// swatch, as the reference lays the palette out.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.name,
    required this.dark,
    required this.light,
    required this.colors,
  });

  final String name;
  final Color dark;
  final Color light;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    Widget half(String mode, Color value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: value,
              borderRadius: BorderRadius.circular(DexRadius.control),
              border: Border.all(
                color: colors.line,
                width: DexStroke.hairline,
              ),
            ),
          ),
          const SizedBox(height: DexSpace.xs),
          Text(mode, style: DexTheme.data(colors, size: 9)),
          Text(
            _hex(value),
            style: DexTheme.data(colors, size: 10, color: colors.text),
          ),
        ],
      ),
    );

    return Container(
      width: 168,
      padding: const EdgeInsets.all(DexSpace.sm),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: colors.line, width: DexStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.text,
            ),
          ),
          const SizedBox(height: DexSpace.sm),
          Row(
            children: <Widget>[
              half('DARK', dark),
              const SizedBox(width: DexSpace.sm),
              half('LIGHT', light),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tabs as underlined labels, as the reference sets them: the selected one
/// carries a signal-coloured rule, the rest sit on the hairline.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.labels,
    required this.selected,
    required this.colors,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final DexColors colors;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.line, width: DexStroke.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Semantics(
              button: true,
              selected: i == selected,
              child: InkWell(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DexSpace.md,
                    vertical: DexSpace.sm,
                  ),
                  constraints: const BoxConstraints(minHeight: DexHit.comfortable),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected ? colors.signal : Colors.transparent,
                        width: DexStroke.focusRing,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: t.labelLarge?.copyWith(
                      color: i == selected ? colors.text : colors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
