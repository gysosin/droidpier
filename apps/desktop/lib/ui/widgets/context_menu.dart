import 'package:flutter/material.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_tokens.dart';

/// One row in a [showDexContextMenu], or a rule between groups.
///
/// Deliberately knows nothing about apps or windows: the drawer's Pin/Unpin and
/// the title bar's snap actions are the same shape, so they share one menu
/// rather than each growing their own.
class DexMenuAction {
  const DexMenuAction({required this.label, required this.onSelected})
    : isSeparator = false;

  /// A rule between groups — snap actions apart from Close, for instance.
  /// Never selectable: a blank row that can be clicked and does nothing is
  /// worse than no row.
  const DexMenuAction.separator()
    : label = '',
      onSelected = _nothing,
      isSeparator = true;

  final String label;
  final VoidCallback onSelected;
  final bool isSeparator;

  static void _nothing() {}
}

/// Opens a context menu at [globalPosition].
///
/// Built on [showMenu] rather than a hand-rolled overlay, which brings edge
/// clamping, barrier dismissal, Escape, focus traversal and screen-reader
/// semantics already correct — all of which a bespoke overlay would have had to
/// re-earn.
Future<void> showDexContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<DexMenuAction> actions,
}) async {
  final DexColors c = Theme.of(context).extension<DexColors>()!;
  final TextTheme t = Theme.of(context).textTheme;

  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final RelativeRect position = RelativeRect.fromLTRB(
    globalPosition.dx,
    globalPosition.dy,
    overlay.size.width - globalPosition.dx,
    overlay.size.height - globalPosition.dy,
  );

  final VoidCallback? chosen = await showMenu<VoidCallback>(
    context: context,
    position: position,
    // A 192 px slate card at radius 12, as the reference draws it.
    color: c.surface.withValues(alpha: 0.95),
    constraints: const BoxConstraints(minWidth: 192, maxWidth: 192),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DexRadius.card),
      side: BorderSide(color: c.line, width: DexStroke.hairline),
    ),
    items: <PopupMenuEntry<VoidCallback>>[
      for (final DexMenuAction a in actions)
        if (a.isSeparator)
          PopupMenuDivider(height: DexSpace.sm, color: c.line)
        else
          PopupMenuItem<VoidCallback>(
            value: a.onSelected,
            height: DexHit.comfortable,
            child: Text(a.label, style: t.bodyMedium?.copyWith(color: c.text)),
          ),
    ],
  );

  chosen?.call();
}
