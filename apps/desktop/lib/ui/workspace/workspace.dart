import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'app_window.dart';
import 'window_model.dart';

/// The composited workspace: Android app windows stacked on the desk.
///
/// Purely presentational. It takes the window list, paints it in z-order, and
/// reports intent — it holds no geometry and decides no state, so there is
/// nothing here to drift out of step with the backend.
class Workspace extends StatefulWidget {
  const Workspace({
    required this.windows,
    required this.intents,
    required this.emptyChild,
    this.snapEnabled = true,
    super.key,
  });

  final List<WorkspaceWindow> windows;
  final WorkspaceIntents intents;

  /// Shown when nothing is open — the desk, so an empty workspace is still a
  /// place rather than a void.
  final Widget emptyChild;

  /// When false, dragging to an edge does nothing — the Settings surface
  /// exposes this, and the toggle must actually change behaviour rather than
  /// merely remember a preference.
  final bool snapEnabled;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  /// The zone the in-flight drag is hovering, if any.
  ///
  /// Presentation state, not backend state: it exists only between pointer
  /// moves and release, and nothing outside this widget can observe it. The
  /// window's actual geometry still comes from the backend.
  WindowSnap? _preview;
  String? _draggingId;

  /// The window with a move or resize gesture in flight.
  ///
  /// Its geometry is applied immediately rather than animated. A window frame
  /// is animated between *discrete* states — snapping, maximising, restoring —
  /// but a drag produces a geometry echo every few milliseconds, and each one
  /// restarted a 180 ms curve. The frame then chased the pointer instead of
  /// following it, which is a large part of what reads as lag.
  String? _interactingId;

  /// Live geometry of a window being dragged. Held here so a title-bar drag
  /// rebuilds only the workspace, not the whole shell; committed to the backend
  /// on release.
  final Map<String, WindowGeometry> _drag = <String, WindowGeometry>{};

  /// The last geometry each window had while *not* snapped.
  ///
  /// Dragging a snapped window off its edge has to give it back the size it had
  /// before, which is what every desktop does and what this did not: snapping
  /// replaced the geometry outright, so a window that had once been snapped
  /// kept the half-screen size for the rest of its life however far it was
  /// dragged.
  ///
  /// Recorded by observing geometry rather than by hooking the snap, so it
  /// covers both ways in — dragging to an edge, and the title bar's menu, which
  /// goes straight to the backend without passing through here.
  final Map<String, WindowGeometry> _lastFree = <String, WindowGeometry>{};

  /// Where the pointer last was, per window, so a restored window can be placed
  /// under the cursor rather than jumping away from it.
  final Map<String, Offset> _pointer = <String, Offset>{};

  /// The snap rectangles for the current workspace size, computed once.
  ///
  /// Cached rather than rebuilt per call. `build` runs on every telemetry
  /// snapshot — constantly while a window streams — and the first cut of this
  /// allocated seven `WindowGeometry` objects per window per build, which is
  /// per-frame garbage over a live video texture.
  Size? _snapRectsFor;
  List<WindowGeometry> _snapRects = const <WindowGeometry>[];

  List<WindowGeometry> _snapRectsIn(Size size) {
    if (_snapRectsFor == size) return _snapRects;
    _snapRectsFor = size;
    _snapRects = <WindowGeometry>[
      for (final WindowSnap snap in WindowSnap.values) snap.geometryIn(size),
    ];
    return _snapRects;
  }

  /// Whether [g] is sitting on one of the snap rectangles for [size].
  ///
  /// Compared with a tolerance because the geometry makes a round trip through
  /// the backend and back, and an exact double match is not guaranteed.
  bool _isSnapped(WindowGeometry g, Size size) {
    for (final WindowGeometry r in _snapRectsIn(size)) {
      if ((g.x - r.x).abs() < 2 &&
          (g.y - r.y).abs() < 2 &&
          (g.width - r.width).abs() < 2 &&
          (g.height - r.height).abs() < 2) {
        return true;
      }
    }
    return false;
  }

  void _setInteracting(String? id) {
    if (_interactingId == id) return;
    setState(() => _interactingId = id);
  }

  void _onDragMove(String id, Offset delta, Size size) {
    WindowGeometry? base = _drag[id];
    if (base == null) {
      final WorkspaceWindow? w = widget.windows
          .cast<WorkspaceWindow?>()
          .firstWhere((WorkspaceWindow? w) => w?.id == id, orElse: () => null);
      if (w == null) return; // window closed mid-drag
      base = w.geometry;

      // Dragging a snapped window off its edge gives it back the size it had
      // before it snapped, and puts it under the cursor rather than leaving it
      // to lurch away from the pointer.
      final WindowGeometry? free = _lastFree[id];
      if (free != null && _isSnapped(base, size)) {
        final Offset? at = _pointer[id];
        final double x = at != null
            ? at.dx - free.width / 2
            : base.x + (base.width - free.width) / 2;
        base = free.copyWith(x: x, y: base.y);
      }
    }
    setState(() {
      _drag[id] = base!
          .copyWith(x: base.x + delta.dx, y: base.y + delta.dy)
          .clampedTo(size);
    });
  }

  void _onDragTo(String id, Offset global, Size size) {
    if (!widget.snapEnabled) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset local = box.globalToLocal(global);
    _pointer[id] = local;
    final WindowSnap? zone = WindowSnap.forPointer(local, size);
    if (zone != _preview || id != _draggingId) {
      setState(() {
        _preview = zone;
        _draggingId = id;
      });
    }
  }

  /// Title-bar drags report position through [_onDragTo], which only fires when
  /// snapping is enabled — so interaction is marked separately, or a drag with
  /// snapping off would still animate.
  void _onMoveStart(String id) => _setInteracting(id);

  void _onDragEnd(Size size) {
    final WindowSnap? zone = _preview;
    final String? id = _interactingId;
    final WindowGeometry? dragged = id != null ? _drag.remove(id) : null;
    setState(() {
      _preview = null;
      _draggingId = null;
      // Released: a snap or restore from here *should* animate.
      _interactingId = null;
    });
    if (id == null) {
      return;
    }
    if (zone == WindowSnap.maximise) {
      widget.intents.setDisplayState(id, WindowDisplayState.maximised);
      return;
    }
    if (zone != null) {
      widget.intents.move(id, zone.geometryIn(size));
      return;
    }
    // No snap zone: commit the window's final dragged position to the backend.
    if (dragged != null) {
      widget.intents.move(id, dragged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);

        // Remember every window's un-snapped geometry, so dragging one off a
        // snap edge can give it back. Skipped while a window is being dragged,
        // or the size it is being restored *to* would immediately overwrite the
        // size it is being restored *from*.
        for (final WorkspaceWindow w in widget.windows) {
          if (w.id == _interactingId) continue;
          if (w.displayState != WindowDisplayState.normal) continue;
          // Cheapest test first: an unchanged geometry needs no snap check at
          // all, which is the common case on a telemetry-driven rebuild.
          final WindowGeometry? known = _lastFree[w.id];
          if (known != null &&
              known.x == w.geometry.x &&
              known.y == w.geometry.y &&
              known.width == w.geometry.width &&
              known.height == w.geometry.height) {
            continue;
          }
          if (_isSnapped(w.geometry, size)) continue;
          _lastFree[w.id] = w.geometry;
        }
        // Only when a window has actually gone: removeWhere allocates a closure
        // and walks the map, and it ran on every frame.
        if (_lastFree.length > widget.windows.length) {
          _lastFree.removeWhere(
            (String id, _) =>
                !widget.windows.any((WorkspaceWindow w) => w.id == id),
          );
        }

        // Minimised windows live in the dock, not the workspace.
        final List<WorkspaceWindow> visible =
            widget.windows
                .where(
                  (WorkspaceWindow w) =>
                      !w.isMinimised &&
                      w.session.status != WindowSessionStatus.closed,
                )
                .toList()
              ..sort(
                (WorkspaceWindow a, WorkspaceWindow b) =>
                    a.zOrder.compareTo(b.zOrder),
              );

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.emptyChild,
            // Preview sits under the windows: it is a hint about where this
            // one will land, not something to obscure the others with.
            if (_preview != null) _SnapPreview(zone: _preview!, size: size),
            for (final WorkspaceWindow w in visible)
              _Positioned(
                key: ValueKey<String>(w.id),
                // While dragging, render this window at its live local geometry
                // so the whole shell need not rebuild on every pointer move.
                window: _drag.containsKey(w.id)
                    ? w.copyWith(geometry: _drag[w.id]!)
                    : w,
                workspaceSize: size,
                intents: widget.intents,
                animated: _interactingId != w.id,
                onDragTo: (Offset p) {
                  _onMoveStart(w.id);
                  _onDragTo(w.id, p, size);
                },
                onDragMove: (Offset delta) => _onDragMove(w.id, delta, size),
                onDragEnd: () => _onDragEnd(size),
                onResizeStart: () => _setInteracting(w.id),
                onResizeEnd: () => _setInteracting(null),
                // Only offered when there is in fact another window to close;
                // otherwise the entry is absent rather than a no-op.
                onCloseOthers: widget.windows.length > 1
                    ? () {
                        for (final WorkspaceWindow other in widget.windows) {
                          if (other.id != w.id) {
                            widget.intents.close(other.id);
                          }
                        }
                      }
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _Positioned extends StatelessWidget {
  const _Positioned({
    required this.window,
    required this.workspaceSize,
    required this.intents,
    this.animated = true,
    this.onDragTo,
    this.onDragMove,
    this.onDragEnd,
    this.onResizeStart,
    this.onResizeEnd,
    this.onCloseOthers,
    super.key,
  });

  final WorkspaceWindow window;
  final Size workspaceSize;
  final WorkspaceIntents intents;

  /// False while this window is being dragged or resized, so geometry lands
  /// on the frame in the same frame the pointer moved.
  final bool animated;

  final ValueChanged<Offset>? onDragTo;
  final ValueChanged<Offset>? onDragMove;
  final VoidCallback? onDragEnd;
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeEnd;

  /// Closes every other window, for the title bar's context menu.
  final VoidCallback? onCloseOthers;

  /// Maximised fills the workspace it is given; the shell has already reserved
  /// the menu bar and dock, so "the workspace" is exactly this box.
  Rect get _rect {
    if (window.displayState != WindowDisplayState.maximised) {
      // Always clamp to the real work area, so a geometry that arrives
      // off-screen — from the backend echo, an aspect-fit, or a stale drag —
      // can never leave the title bar above the top edge, unreachable.
      return window.geometry.clampedTo(workspaceSize).rect;
    }
    // Maximise fills the work area *at the video's own aspect ratio* and
    // centres the result, rather than taking the whole rectangle and leaving
    // black bars where a portrait (or otherwise mismatched) phone screen cannot
    // fill a landscape monitor. The surface then covers the window exactly —
    // no black empty space, and still no stretch.
    final WindowSurface? surface = window.surface;
    if (surface == null ||
        surface.pixelSize.width <= 0 ||
        surface.pixelSize.height <= 0) {
      return Offset.zero & workspaceSize;
    }
    final double aspect =
        surface.pixelSize.width / surface.pixelSize.height;
    double w = workspaceSize.width;
    double h = w / aspect;
    if (h > workspaceSize.height) {
      h = workspaceSize.height;
      w = h * aspect;
    }
    return Rect.fromLTWH(
      (workspaceSize.width - w) / 2,
      (workspaceSize.height - h) / 2,
      w,
      h,
    );
  }

  /// Grab margin around the frame.
  static const double _slop = 8;

  /// How far a handle reaches *inside* the frame.
  ///
  /// Small on purpose. The handles were once painted over the window and
  /// swallowed clicks on the title-bar close button; they were then moved
  /// underneath it, which made them unreachable instead — the window covered
  /// their inner half and the outer half fell outside the box, and Flutter
  /// does not hit-test outside a box. Now the box is grown to contain the
  /// whole grab margin, and the handles sit on top but reach only this far in,
  /// which is nowhere near any button.
  static const double _lip = 2;

  @override
  Widget build(BuildContext context) {
    final Rect r = _rect;
    final bool resizable = window.displayState != WindowDisplayState.maximised;
    // The positioned box is the frame plus its grab margin, so every handle
    // has somewhere to be hit. The window is inset back to its real rect, so
    // none of this changes where it appears.
    final double pad = resizable ? _slop : 0;

    return AnimatedPositioned(
      duration: DexMotion.enabled(context) && animated
          ? DexDuration.standard
          : Duration.zero,
      curve: DexMotion.arrive,
      left: r.left - pad,
      top: r.top - pad,
      width: r.width + pad * 2,
      height: r.height + pad * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: pad,
            top: pad,
            width: r.width,
            height: r.height,
            child: AppWindow(
              window: window,
              intents: intents,
              workspaceSize: workspaceSize,
              onDragTo: onDragTo,
              onDragMove: onDragMove,
              onDragEnd: onDragEnd,
              onCloseOthers: onCloseOthers,
            ),
          ),
          // Painted last so they win the border, which is what a person aims
          // at when resizing.
          if (resizable) ..._resizeHandles(context),
        ],
      ),
    );
  }

  /// Eight handles with hit slop outside the frame, so a hairline border is
  /// still grabbable without making the border itself thick.
  List<Widget> _resizeHandles(BuildContext context) {
    // Offsets are relative to the padded box, so 0 is the outer edge of the
    // grab margin and `_slop` is the window's own border.
    const double band = _slop + _lip;
    Widget handle({
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
      required MouseCursor cursor,
      required void Function(Offset delta) onDrag,
    }) {
      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => onResizeStart?.call(),
            onPanUpdate: (DragUpdateDetails d) => onDrag(d.delta),
            onPanEnd: (_) => onResizeEnd?.call(),
            onPanCancel: () => onResizeEnd?.call(),
          ),
        ),
      );
    }

    void resize({double dx = 0, double dy = 0, double dw = 0, double dh = 0}) {
      final WindowGeometry g = window.geometry;
      final double width = (g.width + dw).clamp(
        WorkspaceGeometry.minimum.width,
        double.infinity,
      );
      final double height = (g.height + dh).clamp(
        WorkspaceGeometry.minimum.height,
        double.infinity,
      );
      // Only move the origin by as much as the size actually changed, or a
      // window being dragged past its minimum slides sideways instead of
      // stopping.
      intents.move(
        window.id,
        g.copyWith(
          x:
              g.x +
              (dw == 0 ? dx : dx * ((width - g.width) / (dw == 0 ? 1 : dw))),
          y:
              g.y +
              (dh == 0 ? dy : dy * ((height - g.height) / (dh == 0 ? 1 : dh))),
          width: width,
          height: height,
        ),
      );
    }

    return <Widget>[
      // Edges: inset at both ends by the band so the corners own their square
      // and an edge drag never turns into a diagonal one.
      handle(
        left: 0,
        top: band,
        bottom: band,
        width: band,
        cursor: SystemMouseCursors.resizeLeftRight,
        onDrag: (Offset d) => resize(dx: d.dx, dw: -d.dx),
      ),
      handle(
        right: 0,
        top: band,
        bottom: band,
        width: band,
        cursor: SystemMouseCursors.resizeLeftRight,
        onDrag: (Offset d) => resize(dw: d.dx),
      ),
      handle(
        top: 0,
        left: band,
        right: band,
        height: band,
        cursor: SystemMouseCursors.resizeUpDown,
        onDrag: (Offset d) => resize(dy: d.dy, dh: -d.dy),
      ),
      handle(
        bottom: 0,
        left: band,
        right: band,
        height: band,
        cursor: SystemMouseCursors.resizeUpDown,
        onDrag: (Offset d) => resize(dh: d.dy),
      ),
      handle(
        left: 0,
        top: 0,
        width: band,
        height: band,
        cursor: SystemMouseCursors.resizeUpLeft,
        onDrag: (Offset d) => resize(dx: d.dx, dy: d.dy, dw: -d.dx, dh: -d.dy),
      ),
      handle(
        right: 0,
        top: 0,
        width: band,
        height: band,
        cursor: SystemMouseCursors.resizeUpRight,
        onDrag: (Offset d) => resize(dy: d.dy, dw: d.dx, dh: -d.dy),
      ),
      handle(
        left: 0,
        bottom: 0,
        width: band,
        height: band,
        cursor: SystemMouseCursors.resizeDownLeft,
        onDrag: (Offset d) => resize(dx: d.dx, dw: -d.dx, dh: d.dy),
      ),
      handle(
        right: 0,
        bottom: 0,
        width: band,
        height: band,
        cursor: SystemMouseCursors.resizeDownRight,
        onDrag: (Offset d) => resize(dw: d.dx, dh: d.dy),
      ),
    ];
  }
}

/// Where a window lands when it opens.
///
/// Cascaded rather than centred: two apps opened in a row must both be visible,
/// which M8 requires, and centring would stack them exactly on top of each
/// other.
WindowGeometry cascadeGeometry(int index, Size workspace) {
  const double step = 34;
  final double width = (workspace.width * 0.52).clamp(
    WorkspaceGeometry.minimum.width,
    900,
  );
  final double height = (workspace.height * 0.62).clamp(
    WorkspaceGeometry.minimum.height,
    720,
  );
  final double offset = step * (index % 6);
  return WindowGeometry(
    x: (workspace.width - width) / 2 - step * 2 + offset,
    y: (workspace.height - height) / 2 - step + offset,
    width: width,
    height: height,
  ).clampedTo(workspace);
}

/// A stand-in for real frames, for tests and goldens.
///
/// A real window now carries a `WindowSurface` with a texture id, and a texture
/// id paints nothing outside a running host — so widget tests still need
/// something that renders. Deliberately obvious — a labelled panel, not a fake
/// screenshot — so nobody mistakes a mock for a working stream while reviewing.
WidgetBuilder mockSurface(AndroidApplication app, DexColors colors) {
  return (BuildContext context) => ColoredBox(
    color: colors.raised,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            app.label,
            style: TextStyle(
              fontFamily: DexType.display,
              fontFamilyFallback: DexType.displayFallback,
              fontSize: 96,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: DexSpace.lg),
          Text(
            'mock frame surface',
            style: TextStyle(
              fontFamily: DexType.data,
              fontFamilyFallback: DexType.dataFallback,
              fontSize: 48,
              color: colors.muted.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Where the window will land if the drag is released now.
///
/// Shown before release rather than after, so a snap is never a surprise —
/// a window that jumps somewhere unannounced reads as a bug.
class _SnapPreview extends StatelessWidget {
  const _SnapPreview({required this.zone, required this.size});

  final WindowSnap zone;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final Rect r = zone.geometryIn(size).rect;
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: c.signal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(DexRadius.card),
            border: Border.all(color: c.signal, width: DexStroke.focusRing),
          ),
          alignment: Alignment.center,
          child: Text(zone.label, style: DexTheme.data(c, color: c.signal)),
        ),
      ),
    );
  }
}
