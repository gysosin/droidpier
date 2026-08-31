import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../widgets/bench_backdrop.dart';

/// Permissions.
///
/// A capability the phone has not granted is not an error — it is a feature
/// that is off, with a way to turn it on. Each row therefore states what the
/// capability does for the person, its current grant, and the one action that
/// changes it. Nothing here dead-ends.
class PermissionPanel extends StatelessWidget {
  const PermissionPanel({
    required this.permissions,
    this.onGrant,
    this.onOpenSettings,
    super.key,
  });

  final PermissionState permissions;

  /// Grants a capability. Null while `OpenDexFacade` has no command for it —
  /// see `docs/ARCHITECTURE.md` for the facade boundary. Null renders guidance
  /// instead of a button, because a control that does nothing when pressed is
  /// worse than no control.
  final ValueChanged<String>? onGrant;

  /// Opens this capability's screen on the phone, or null if the backend
  /// cannot open that particular one.
  ///
  /// A resolver rather than one callback for the whole panel: the backend can
  /// open notification access and nothing else, so a single callback would put
  /// a "Manage" button on every row and fail on all but one. Returning null
  /// per capability makes that structurally impossible.
  final VoidCallback? Function(String capability)? onOpenSettings;

  /// UI owns the words. Keys are the contract's; labels are the person's.
  static const Map<String, (String, String)> _copy = <String, (String, String)>{
    'notifications': (
      'Notifications',
      'Show your phone’s notifications on the desk.',
    ),
    'media': ('Media controls', 'Play, pause, and skip from the desk.'),
    'audio': ('Audio', 'Hear your phone through this computer.'),
    'clipboard': ('Clipboard', 'Copy on one device, paste on the other.'),
    'calls': ('Calls', 'Answer and end calls without picking up the phone.'),
  };

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    // Ordered by what needs doing, not by key. Structure is information:
    // anything the person must act on rises to the top, what is already on
    // sits below, and what this phone cannot do sinks to the bottom.
    int rank(PermissionGrant g) => switch (g) {
      PermissionGrant.requiresSettings => 0,
      PermissionGrant.denied => 1,
      PermissionGrant.granted => 2,
      PermissionGrant.unavailable => 3,
    };
    final List<MapEntry<String, PermissionGrant>> entries =
        permissions.grants.entries.toList()..sort((
          MapEntry<String, PermissionGrant> a,
          MapEntry<String, PermissionGrant> b,
        ) {
          final int byRank = rank(a.value).compareTo(rank(b.value));
          return byRank != 0 ? byRank : a.key.compareTo(b.key);
        });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BenchBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DexSpace.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('What the desk can use', style: t.headlineMedium),
                    const SizedBox(height: DexSpace.sm),
                    Text(
                      'Everything here is optional. Turn on only what you want.',
                      style: t.bodyLarge?.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: DexSpace.xl),
                    if (permissions.status == LoadStatus.loading)
                      _Skeleton(colors: c)
                    else if (entries.isEmpty)
                      _Empty(colors: c)
                    else
                      for (final MapEntry<String, PermissionGrant> e in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: DexSpace.sm),
                          child: _PermissionRow(
                            id: e.key,
                            grant: e.value,
                            copy: _copy[e.key],
                            colors: c,
                            onGrant: onGrant,
                            onOpenSettings: onOpenSettings,
                          ),
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

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.id,
    required this.grant,
    required this.copy,
    required this.colors,
    this.onGrant,
    this.onOpenSettings,
  });

  final String id;
  final PermissionGrant grant;
  final (String, String)? copy;
  final DexColors colors;
  final ValueChanged<String>? onGrant;
  final VoidCallback? Function(String capability)? onOpenSettings;

  String get _title => copy?.$1 ?? id;
  String get _detail => copy?.$2 ?? 'Capability reported by the phone.';

  /// State word plus the colour that carries it.
  (String, Color) get _state => switch (grant) {
    PermissionGrant.granted => ('On', colors.signal),
    PermissionGrant.denied => ('Off', colors.muted),
    PermissionGrant.requiresSettings => ('Needs phone settings', colors.fault),
    PermissionGrant.unavailable => ('Not on this phone', colors.muted),
  };

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final (String stateLabel, Color stateColor) = _state;

    final bool dimmed = grant == PermissionGrant.unavailable;

    return Opacity(
      // Unavailable is not a broken row — it recedes so the eye skips past it.
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(DexSpace.md),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: dimmed ? 0.4 : 0.72),
          borderRadius: BorderRadius.circular(DexRadius.card),
          border: Border.all(color: colors.line, width: DexStroke.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_title, style: t.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    _detail,
                    style: t.bodyMedium?.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: DexSpace.xs),
                  // The key is not shown: it only echoes the title. The
                  // state is the machine value worth reading.
                  Text(
                    stateLabel,
                    style: DexTheme.data(colors, size: 11, color: stateColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: DexSpace.md),
            // Fixed action column so the right edge stays straight however the
            // labels differ in length.
            SizedBox(width: 152, child: Align(child: _action(context))),
          ],
        ),
      ),
    );
  }

  /// One action per state, named for what it does. `unavailable` is the only
  /// row with no action, and it says why rather than showing a dead control.
  /// One action per state, named for what it does.
  ///
  /// Where the facade cannot perform the action, the row says what to do on the
  /// phone instead of showing a button that would do nothing.
  Widget _action(BuildContext context) {
    final TextStyle? hint = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: colors.muted);

    switch (grant) {
      case PermissionGrant.granted:
        final VoidCallback? manage = onOpenSettings?.call(id);
        if (manage == null) {
          return const SizedBox.shrink();
        }
        return OutlinedButton(onPressed: manage, child: const Text('Manage'));
      case PermissionGrant.denied:
        if (onGrant == null) {
          return Text('Turn on from the phone', style: hint, softWrap: true);
        }
        return FilledButton(
          onPressed: () => onGrant!(id),
          child: const Text('Turn on'),
        );
      case PermissionGrant.requiresSettings:
        final VoidCallback? open = onOpenSettings?.call(id);
        if (open == null) {
          return Text('Allow on the phone', style: hint, softWrap: true);
        }
        return OutlinedButton(
          onPressed: open,
          child: const Text('Open on phone'),
        );
      case PermissionGrant.unavailable:
        return const SizedBox.shrink();
    }
  }
}

/// Skeletons mirror the real rows so nothing shifts when data lands.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          Container(
            height: 92,
            margin: const EdgeInsets.only(bottom: DexSpace.sm),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(DexRadius.card),
              border: Border.all(color: colors.line, width: DexStroke.hairline),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});

  final DexColors colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DexSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(DexRadius.card),
        border: Border.all(color: colors.line, width: DexStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Nothing to allow yet', style: t.bodyLarge),
          const SizedBox(height: DexSpace.xs),
          Text(
            'Connect a phone and its capabilities will appear here.',
            style: t.bodyMedium?.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}
