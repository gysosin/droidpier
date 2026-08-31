import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';
import '../util/app_display_name.dart';
import 'app_glyph.dart';

/// App drawer.
///
/// A real device reports on the order of eighty applications, so the drawer is
/// built around finding one rather than around browsing all of them: the search
/// field holds focus on open, typing filters, and Enter launches the first
/// match. Apps are split into System and User sections, as the reference has
/// it, so the handful of system tools sit apart from everything installed.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    required this.status,
    required this.applications,
    required this.onLaunch,
    required this.onRefresh,
    required this.onDismiss,
    super.key,
  });

  final LoadStatus status;
  final List<AndroidApplication> applications;
  final ValueChanged<String> onLaunch;
  final VoidCallback onRefresh;

  /// Tapping the blurred area behind the icons dismisses the drawer.
  final VoidCallback onDismiss;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The drawer opens ready to type. Anything else costs a click.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _matches(AndroidApplication a) {
    final String q = _query.text.trim().toLowerCase();
    return q.isEmpty ||
        a.label.toLowerCase().contains(q) ||
        a.packageName.toLowerCase().contains(q);
  }

  static int _byLabel(AndroidApplication a, AndroidApplication b) =>
      a.label.toLowerCase().compareTo(b.label.toLowerCase());

  List<AndroidApplication> get _systemApps => widget.applications
      .where((AndroidApplication a) => a.isSystemApp && _matches(a))
      .toList()
    ..sort(_byLabel);

  List<AndroidApplication> get _userApps => widget.applications
      .where((AndroidApplication a) => !a.isSystemApp && _matches(a))
      .toList()
    ..sort(_byLabel);

  void _launchFirst() {
    // User apps are what people reach for; only fall back to a system match.
    final List<AndroidApplication> user = _userApps;
    final List<AndroidApplication> first = user.isNotEmpty ? user : _systemApps;
    if (first.isNotEmpty) {
      widget.onLaunch(first.first.packageName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    // A floating launcher panel: the desk dims behind a large rounded glass
    // card that carries the apps in a System /
    // User split, with the search field pinned along the bottom. Tapping the
    // dimmed desk dismisses it.
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.42
                      : 0.24,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DexSpace.xxl,
              vertical: DexSpace.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: GlassPanel(
                  radius: DexRadius.panel,
                  blur: 32,
                  padding: const EdgeInsets.fromLTRB(
                    DexSpace.xl,
                    DexSpace.xl,
                    DexSpace.xl,
                    DexSpace.lg,
                  ),
                  // The tap-to-dismiss is the scrim behind; taps inside the
                  // panel must not fall through to it.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Column(
                      children: <Widget>[
                        Expanded(child: _body(context, c, t)),
                        const SizedBox(height: DexSpace.md),
                        // The search field lives along the bottom of the panel,
                        // as the reference has it — wide, not a slim toolbar.
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _SearchField(
                              controller: _query,
                              focusNode: _searchFocus,
                              colors: c,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _launchFirst(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, DexColors c, TextTheme t) {
    if (widget.status == LoadStatus.loading) {
      return _Skeleton(colors: c);
    }
    if (widget.applications.isEmpty) {
      return _Notice(
        title: 'No apps yet',
        detail: 'Connect a phone and its apps will appear here.',
        actionLabel: 'Look again',
        onAction: widget.onRefresh,
        colors: c,
      );
    }

    final List<AndroidApplication> system = _systemApps;
    final List<AndroidApplication> user = _userApps;

    if (system.isEmpty && user.isEmpty) {
      return _Notice(
        title: 'Nothing matches “${_query.text.trim()}”',
        detail: 'Try a shorter search.',
        actionLabel: 'Clear search',
        onAction: () {
          _query.clear();
          setState(() {});
          _searchFocus.requestFocus();
        },
        colors: c,
      );
    }

    // Sectioned, System then User — the reference order. Empty sections (which
    // happen while searching) drop out rather than leaving a bare header.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: DexSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (system.isNotEmpty) ...<Widget>[
            _SectionHeader(label: 'System apps', colors: c),
            _AppGrid(apps: system, colors: c, onLaunch: widget.onLaunch),
          ],
          if (system.isNotEmpty && user.isNotEmpty)
            const SizedBox(height: DexSpace.lg),
          if (user.isNotEmpty) ...<Widget>[
            _SectionHeader(label: 'User apps', colors: c),
            _AppGrid(apps: user, colors: c, onLaunch: widget.onLaunch),
          ],
        ],
      ),
    );
  }
}

/// An uppercase, letter-spaced section label, as the reference sets above each
/// block of apps.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.colors});

  final String label;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: DexSpace.xs,
        bottom: DexSpace.md,
      ),
      child: Text(
        label.toUpperCase(),
        style: DexTheme.data(
          colors,
          size: 11,
          color: colors.muted,
        ).copyWith(letterSpacing: 1.6),
      ),
    );
  }
}

/// A non-scrolling grid of app tiles, sized to its content so several can stack
/// inside one scroll view.
class _AppGrid extends StatelessWidget {
  const _AppGrid({
    required this.apps,
    required this.colors,
    required this.onLaunch,
  });

  final List<AndroidApplication> apps;
  final DexColors colors;
  final ValueChanged<String> onLaunch;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 116,
        mainAxisExtent: 108,
        crossAxisSpacing: DexSpace.md,
        mainAxisSpacing: DexSpace.md,
      ),
      itemCount: apps.length,
      itemBuilder: (BuildContext context, int i) => _AppTile(
        app: apps[i],
        colors: colors,
        onLaunch: () => onLaunch(apps[i].packageName),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.colors,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DexColors colors;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      cursorColor: colors.signal,
      decoration: InputDecoration(
        // Placeholder ends with an ellipsis and shows the shape of the answer.
        hintText: 'Search apps…',
        hintStyle: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: colors.muted),
        prefixIcon: Icon(Icons.search, size: 18, color: colors.muted),
        filled: true,
        fillColor: colors.surface.withValues(alpha: 0.72),
        contentPadding: const EdgeInsets.symmetric(vertical: DexSpace.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DexRadius.control),
          borderSide: BorderSide(color: colors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DexRadius.control),
          borderSide: BorderSide(color: colors.line),
        ),
        // Focus out-contrasts rest.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DexRadius.control),
          borderSide: BorderSide(
            color: colors.signal,
            width: DexStroke.focusRing,
          ),
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.colors,
    required this.onLaunch,
  });

  final AndroidApplication app;
  final DexColors colors;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool placeholder = isPlaceholderLabel(app.label, app.packageName);
    final String shown = placeholder
        ? displayNameFor(app.packageName)
        : app.label;

    return Semantics(
      button: true,
      label: 'Open $shown',
      child: HoverLift(
        builder: (BuildContext context, bool hovered) => InkWell(
          onTap: onLaunch,
          borderRadius: BorderRadius.circular(DexRadius.card),
          child: AnimatedContainer(
            duration: DexDuration.micro,
            curve: DexMotion.arrive,
            padding: const EdgeInsets.all(DexSpace.sm),
            // Borderless: the icon floats over the blurred desk, with only a
            // faint rounded highlight on hover — no boxed tile.
            decoration: BoxDecoration(
              color: hovered
                  ? DexGlass.of(context).fill
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DexRadius.card),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // AppGlyph, not a local Image.memory: it caches one MemoryImage
                // per package, so the grid does not re-decode (and blink) every
                // time the shell rebuilds — which media/telemetry updates now do
                // often.
                AppGlyph(app: app, size: 40),
                const SizedBox(height: DexSpace.sm),
                Text(
                  placeholder ? displayNameFor(app.packageName) : app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.labelSmall?.copyWith(color: colors.text),
                ),
                if (placeholder)
                  // The derived name is a guess, so the package it came from
                  // stays visible beneath it. A guess must never hide the truth.
                  Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: DexTheme.data(colors, size: 9),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    // Mirrors the real grid exactly, so nothing shifts when apps arrive.
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisExtent: 116,
        crossAxisSpacing: DexSpace.md,
        mainAxisSpacing: DexSpace.md,
      ),
      itemCount: 12,
      itemBuilder: (BuildContext context, int i) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(DexRadius.card),
          border: Border.all(color: colors.line, width: DexStroke.hairline),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
    required this.colors,
  });

  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;
  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: t.bodyLarge),
          const SizedBox(height: DexSpace.xs),
          Text(detail, style: t.bodyMedium?.copyWith(color: colors.muted)),
          const SizedBox(height: DexSpace.lg),
          // An empty screen is an invitation to act, never a dead end.
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
