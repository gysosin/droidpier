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

/// Every notification from the phone, grouped by the app that sent it.
///
/// The desk widget shows three and a count. That is right for a glance and
/// useless for actually reading them, which is what a notification centre is
/// for — the reference has one and this did not.
///
/// The phone stays the source of truth. Dismissing does **not** remove the item
/// locally — it asks the phone and waits for the item to leave
/// `OpenDexSnapshot.notifications`. Removing it optimistically would show a
/// notification as gone that is still sitting on the phone's shade, which is
/// worse than a moment of latency. While the request is in flight the row says
/// so rather than going still.
class NotificationCenter extends StatefulWidget {
  const NotificationCenter({
    required this.notifications,
    required this.status,
    required this.applications,
    required this.now,
    required this.onClose,
    required this.onDismiss,
    required this.onActivate,
    required this.onDismissAll,
    this.onOpenPermissions,
    super.key,
  });

  final List<NotificationItem> notifications;
  final LoadStatus status;

  /// Used only to find an icon for the sending package.
  final List<AndroidApplication> applications;

  final DateTime now;
  final VoidCallback onClose;

  /// Asks the phone to dismiss one notification. Resolves when the phone has
  /// answered, not when the item disappears.
  final Future<void> Function(String id) onDismiss;

  /// Opens the notification on the phone — what tapping it there would do.
  final Future<void> Function(String id) onActivate;

  final Future<void> Function() onDismissAll;

  /// Shown when notification access has not been granted. Null hides the row.
  final VoidCallback? onOpenPermissions;

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  /// Ids with a dismiss in flight. Cleared when the phone answers, whether or
  /// not the item actually went away — an item that stays is a real answer,
  /// and the error reaches the person through the reporting facade.
  final Set<String> _pending = <String>{};

  Future<void> _dismiss(String id) async {
    setState(() => _pending.add(id));
    try {
      await widget.onDismiss(id);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _dismissAll() async {
    final Set<String> ids = widget.notifications
        .map((NotificationItem n) => n.id)
        .toSet();
    setState(() => _pending.addAll(ids));
    try {
      await widget.onDismissAll();
    } finally {
      if (mounted) setState(() => _pending.removeAll(ids));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    final List<NotificationItem> ordered = widget.notifications.toList()
      ..sort(
        (NotificationItem a, NotificationItem b) =>
            b.timestamp.compareTo(a.timestamp),
      );

    return Semantics(
      container: true,
      label: 'Notifications',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.35),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  DexSpace.lg,
                  DexSpace.lg,
                  56 + DexSpace.md,
                ),
                child: Entrance(
                  rise: 0,
                  child: SizedBox(
                    width: 380,
                    child: GlassPanel(
                      radius: DexRadius.dialog,
                      fill: glass.substrate,
                      padding: const EdgeInsets.all(DexSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              // Expanded, not Spacer-padded: the title, the
                              // count, a button and a close in 348 px of panel
                              // overflowed by 108 the moment the button
                              // arrived.
                              Expanded(
                                child: Row(
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        'Notifications',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.titleLarge,
                                      ),
                                    ),
                                    if (ordered.isNotEmpty) ...<Widget>[
                                      const SizedBox(width: DexSpace.sm),
                                      Text(
                                        '${ordered.length}',
                                        style: DexTheme.data(c, size: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (ordered.isNotEmpty) ...<Widget>[
                                TextButton(
                                  // Clearing a backlog one at a time is the
                                  // main reason people stop opening these.
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: DexSpace.sm,
                                    ),
                                    minimumSize: const Size(0, DexHit.minimum),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: _pending.isEmpty
                                      ? _dismissAll
                                      : null,
                                  child: const Text('Clear all'),
                                ),
                                const SizedBox(width: DexSpace.xs),
                              ],
                              _CloseButton(onClose: widget.onClose),
                            ],
                          ),
                          const SizedBox(height: DexSpace.md),
                          Expanded(
                            child: switch (widget.status) {
                              LoadStatus.unavailable => _Blocked(
                                colors: c,
                                onOpenPermissions: widget.onOpenPermissions,
                              ),
                              _ when ordered.isEmpty => _Empty(colors: c),
                              _ => _List(
                                items: ordered,
                                applications: widget.applications,
                                now: widget.now,
                                pending: _pending,
                                onDismiss: _dismiss,
                                onActivate: widget.onActivate,
                              ),
                            },
                          ),
                        ],
                      ),
                    ),
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

class _List extends StatelessWidget {
  const _List({
    required this.items,
    required this.applications,
    required this.now,
    required this.pending,
    required this.onDismiss,
    required this.onActivate,
  });

  final List<NotificationItem> items;
  final List<AndroidApplication> applications;
  final DateTime now;
  final Set<String> pending;
  final Future<void> Function(String id) onDismiss;
  final Future<void> Function(String id) onActivate;

  @override
  Widget build(BuildContext context) {
    // Grouped by sender and kept in most-recent-first order, which is how
    // people actually scan a backlog: by who, then by when.
    final Map<String, List<NotificationItem>> byPackage =
        <String, List<NotificationItem>>{};
    for (final NotificationItem n in items) {
      byPackage.putIfAbsent(n.packageName, () => <NotificationItem>[]).add(n);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final MapEntry<String, List<NotificationItem>> group
            in byPackage.entries)
          _Group(
            packageName: group.key,
            items: group.value,
            applications: applications,
            now: now,
            pending: pending,
            onDismiss: onDismiss,
            onActivate: onActivate,
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.packageName,
    required this.items,
    required this.applications,
    required this.now,
    required this.pending,
    required this.onDismiss,
    required this.onActivate,
  });

  final String packageName;
  final List<NotificationItem> items;
  final List<AndroidApplication> applications;
  final DateTime now;
  final Set<String> pending;
  final Future<void> Function(String id) onDismiss;
  final Future<void> Function(String id) onActivate;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    final AndroidApplication app = applications.firstWhere(
      (AndroidApplication a) => a.packageName == packageName,
      // The sender may not be in the launcher list at all — a system service,
      // or an app installed since the last scan. A derived name beats a raw
      // package name, and both beat hiding the notification.
      orElse: () => AndroidApplication(
        packageName: packageName,
        label: displayNameFor(packageName),
      ),
    );
    final String sender = isPlaceholderLabel(app.label, app.packageName)
        ? displayNameFor(app.packageName)
        : app.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppGlyph(app: app, size: 20),
              const SizedBox(width: DexSpace.sm),
              Expanded(
                child: Text(
                  sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: DexSpace.sm),
          for (final NotificationItem n in items)
            _Item(
              item: n,
              now: now,
              colors: c,
              dismissing: pending.contains(n.id),
              onDismiss: () => onDismiss(n.id),
              onActivate: () => onActivate(n.id),
            ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.item,
    required this.now,
    required this.colors,
    required this.dismissing,
    required this.onDismiss,
    required this.onActivate,
  });

  final NotificationItem item;
  final DateTime now;
  final DexColors colors;
  final bool dismissing;
  final VoidCallback onDismiss;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final DexGlass glass = DexGlass.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: DexSpace.sm),
      child: Semantics(
        button: true,
        label: 'Open ${item.title} on the phone',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => Opacity(
            // Dimmed, not removed: the phone owns the list, and showing an
            // item as gone before the phone agrees would be a lie about the
            // shade.
            opacity: dismissing ? 0.45 : 1,
            child: InkWell(
              onTap: dismissing ? null : onActivate,
              borderRadius: BorderRadius.circular(DexRadius.card),
              child: AnimatedContainer(
                duration: DexDuration.micro,
                curve: DexMotion.arrive,
                width: double.infinity,
                padding: const EdgeInsets.all(DexSpace.md),
                decoration: BoxDecoration(
                  color: hovered && !dismissing ? glass.fill : glass.fillSubtle,
                  borderRadius: BorderRadius.circular(DexRadius.card),
                  border: Border.all(
                    color: hovered && !dismissing
                        ? glass.strokeStrong
                        : glass.stroke,
                    width: DexStroke.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title,
                            style: t.labelLarge?.copyWith(color: colors.text),
                          ),
                        ),
                        const SizedBox(width: DexSpace.sm),
                        Text(
                          dismissing
                              ? 'Dismissing…'
                              : _ago(now, item.timestamp),
                          style: DexTheme.data(colors, size: 10),
                        ),
                        const SizedBox(width: DexSpace.xs),
                        _DismissButton(
                          title: item.title,
                          enabled: !dismissing,
                          onDismiss: onDismiss,
                        ),
                      ],
                    ),
                    if (item.body.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        item.body,
                        style: t.bodyMedium?.copyWith(color: colors.muted),
                      ),
                    ],
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

/// Notification access was never granted, so there is nothing to show and a
/// clear thing to do about it.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.colors, required this.onOpenPermissions});

  final DexColors colors;
  final VoidCallback? onOpenPermissions;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Notifications are turned off',
          style: t.bodyLarge?.copyWith(color: colors.text),
        ),
        const SizedBox(height: DexSpace.xs),
        Text(
          'The phone has not granted notification access, so nothing reaches '
          'the desk.',
          style: t.bodyMedium?.copyWith(color: colors.muted),
        ),
        if (onOpenPermissions != null) ...<Widget>[
          const SizedBox(height: DexSpace.md),
          OutlinedButton(
            onPressed: onOpenPermissions,
            child: const Text('What the desk can use…'),
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Nothing new', style: t.bodyLarge?.copyWith(color: colors.text)),
        const SizedBox(height: DexSpace.xs),
        Text(
          "Notifications from the phone appear here while it's connected.",
          style: t.bodyMedium?.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    return Semantics(
      button: true,
      label: 'Close notifications',
      child: Tooltip(
        message: 'Close',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(DexRadius.control),
            child: Container(
              width: DexHit.comfortable,
              height: DexHit.comfortable,
              decoration: BoxDecoration(
                color: hovered ? glass.fillStrong : glass.fill,
                borderRadius: BorderRadius.circular(DexRadius.control),
                border: Border.all(
                  color: hovered ? glass.strokeStrong : glass.stroke,
                  width: DexStroke.hairline,
                ),
              ),
              child: Icon(Icons.close, size: 15, color: c.text),
            ),
          ),
        ),
      ),
    );
  }
}

String _ago(DateTime now, DateTime then) {
  final Duration d = now.difference(then);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return '${d.inDays} d';
}

/// Dismisses one notification on the phone.
class _DismissButton extends StatelessWidget {
  const _DismissButton({
    required this.title,
    required this.enabled,
    required this.onDismiss,
  });

  final String title;
  final bool enabled;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Dismiss $title',
      child: Tooltip(
        message: 'Dismiss',
        child: HoverLift(
          builder: (BuildContext context, bool hovered) => InkWell(
            onTap: enabled ? onDismiss : null,
            borderRadius: BorderRadius.circular(DexRadius.pill),
            // The glyph is small; the target is not.
            child: SizedBox(
              width: DexHit.minimum,
              height: DexHit.minimum,
              child: Icon(
                Icons.close,
                size: 13,
                color: hovered && enabled ? c.text : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
