import 'dart:async';
import 'package:flutter/material.dart';
import '../util/error_guidance.dart';
import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../motion/dex_motion.dart';
import '../widgets/context_menu.dart';
import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import 'window_input.dart';
import 'window_model.dart';

/// One app window, composited in the workspace.
///
/// The title bar is chrome the desk owns; the body belongs to the Android app.
/// That split decides the interaction: dragging is title-bar only, because a
/// drag started in the body would steal input the app needs.
class AppWindow extends StatelessWidget {
  const AppWindow({
    required this.window,
    required this.intents,
    required this.workspaceSize,
    this.onDragTo,
    this.onDragMove,
    this.onDragEnd,
    this.onCloseOthers,
    super.key,
  });

  final WorkspaceWindow window;
  final WorkspaceIntents intents;
  final Size workspaceSize;

  /// Reports the pointer during a title-bar drag, in workspace coordinates, so
  /// the workspace can preview a snap. The window itself deliberately does not
  /// decide snapping: only the workspace knows where the edges are.
  final ValueChanged<Offset>? onDragTo;

  /// Reports each drag delta so the workspace can move the window in its own
  /// local state — the whole shell no longer rebuilds on every pointer move.
  final ValueChanged<Offset>? onDragMove;
  final VoidCallback? onDragEnd;

  /// Closes every other window. Null where the shell has not supplied it, in
  /// which case the entry is absent rather than inert.
  final VoidCallback? onCloseOthers;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final WindowInput input = _inputFor(window, intents);
    final bool failed = window.session.status == WindowSessionStatus.failed;

    return Semantics(
      label: '${window.session.application.label} window',
      selected: window.isFocused,
      child: Listener(
        // A Listener, not a GestureDetector: focusing on pointer-down must not
        // compete in the gesture arena. As a tap recogniser it lost to the
        // title bar's double-tap and to drags, so clicking a background window
        // silently failed to focus it.
        onPointerDown: (_) {
          intents.focus(window.id);
          intents.raise(window.id);
        },
        child: AnimatedContainer(
          duration: DexDuration.micro,
          curve: DexMotion.arrive,
          decoration: BoxDecoration(
            color: glass.substrate,
            borderRadius: BorderRadius.circular(DexRadius.panel),
            border: Border.all(
              // The reference separates focused from unfocused by *edge
              // brightness*, not by hue: white/40 against white/20. Colour is
              // reserved for the states that actually mean something — a
              // failed window keeps the fault edge.
              color: failed
                  ? c.fault
                  : window.isFocused
                  ? glass.strokeStrong
                  : glass.stroke,
              width: window.isFocused
                  ? DexStroke.focusRing
                  : DexStroke.hairline,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: window.isFocused ? 0.45 : 0.28,
                ),
                blurRadius: window.isFocused ? 40 : 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DexRadius.panel),
            child: Column(
              // Stretch, or the body sizes to the portrait video's width and the
              // semi-transparent window glass — showing the desk — fills the
              // rest. Stretched, the black letterbox in _Surface covers the full
              // width, so a maximised portrait app is bordered by black, not the
              // desk, and the video still keeps its aspect (no stretch).
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TitleBar(
                  window: window,
                  intents: intents,
                  workspaceSize: workspaceSize,
                  onDragTo: onDragTo,
                  onDragMove: onDragMove,
                  onDragEnd: onDragEnd,
                  onCloseOthers: onCloseOthers,
                ),
                Expanded(
                  child: input.wrap(
                    // Only the focused window receives input; an unfocused one
                    // must not swallow events meant for the window on top.
                    enabled: window.isFocused,
                    child: _Body(window: window, intents: intents),
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

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.window,
    required this.intents,
    required this.workspaceSize,
    this.onDragTo,
    this.onDragMove,
    this.onDragEnd,
    this.onCloseOthers,
  });

  final WorkspaceWindow window;
  final WorkspaceIntents intents;
  final Size workspaceSize;
  final ValueChanged<Offset>? onDragTo;
  final ValueChanged<Offset>? onDragMove;
  final VoidCallback? onDragEnd;

  /// Closes every other window. Null where the shell has not supplied it,
  /// in which case the entry is absent rather than inert.
  final VoidCallback? onCloseOthers;

  /// The title-bar menu.
  ///
  /// Carries only what `WorkspaceIntents` can actually perform. The roadmap
  /// also asked for "always on top" and "move to workspace"; there is no
  /// always-on-top anywhere in the window API, and workspaces do not exist
  /// yet, so neither ships — not even greyed out. A control that does nothing
  /// is worse than no control.
  void _showMenu(BuildContext context, Offset at) {
    final bool maximised =
        window.displayState == WindowDisplayState.maximised;

    showDexContextMenu(
      context: context,
      globalPosition: at,
      actions: <DexMenuAction>[
        // Labels and geometry both come from WindowSnap, which already spells
        // them the way a person would: "Left half", "Top right quarter".
        for (final WindowSnap snap in WindowSnap.values)
          if (snap != WindowSnap.maximise)
            DexMenuAction(
              label: snap.label,
              onSelected: () => intents.move(
                window.id,
                snap.geometryIn(workspaceSize),
              ),
            ),
        const DexMenuAction.separator(),
        DexMenuAction(
          label: rotateActionLabel(window.geometry),
          onSelected: _rotate,
        ),
        DexMenuAction(
          // Says what the click will do, not what the window currently is.
          label: maximised ? 'Restore' : 'Maximise',
          onSelected: _toggleMaximise,
        ),
        DexMenuAction(
          label: 'Minimise',
          onSelected: () => intents.setDisplayState(
            window.id,
            WindowDisplayState.minimised,
          ),
        ),
        // Absent rather than disabled where the host has no fullscreen
        // surface, matching what the title bar's own button does.
        if (intents.fullscreen case final ValueChanged<String> enter)
          DexMenuAction(
            label: 'Fullscreen',
            onSelected: () => enter(window.id),
          ),
        const DexMenuAction.separator(),
        DexMenuAction(
          label: 'Close',
          onSelected: () => intents.close(window.id),
        ),
        if (onCloseOthers != null)
          DexMenuAction(label: 'Close others', onSelected: onCloseOthers!),
      ],
    );
  }

  /// Turns the window portrait or landscape.
  ///
  /// Leaves snap or maximise first: neither survives a resize meaningfully, and
  /// a maximised window that quietly became portrait while still flagged
  /// maximised would confuse every later Restore.
  ///
  /// One-shot. The Android app remains free to request its own orientation
  /// afterwards; this is not a rotation lock, which would need backend policy.
  void _rotate() {
    if (window.displayState != WindowDisplayState.normal) {
      intents.setDisplayState(window.id, WindowDisplayState.normal);
    }
    intents.move(
      window.id,
      rotatedGeometry(window.geometry, workspaceSize),
    );
  }

  void _toggleMaximise() {
    intents.setDisplayState(
      window.id,
      window.displayState == WindowDisplayState.maximised
          ? WindowDisplayState.normal
          : WindowDisplayState.maximised,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    // The gesture detector wraps the label only, never the buttons.
    //
    // `onDoubleTap` holds a single tap pending to see whether a second follows.
    // With the buttons inside that detector it swallowed every click on close,
    // minimise and maximise — they were unreachable while looking perfectly
    // normal. The drag region has no business covering them either.
    final Widget draggableLabel = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _toggleMaximise,
      // Deliberately on the label region only. A detector wrapping the window
      // buttons once swallowed every click on close, minimise and maximise
      // while looking perfectly normal.
      onSecondaryTapDown: (TapDownDetails d) =>
          _showMenu(context, d.globalPosition),
      // Intent is streamed during the drag; the UI holds no local position, so
      // a move the backend clamps or rejects cannot leave the window showing a
      // place it is not.
      onPanEnd: (_) => onDragEnd?.call(),
      onPanCancel: () => onDragEnd?.call(),
      onPanUpdate: (DragUpdateDetails d) {
        onDragTo?.call(d.globalPosition);
        if (window.displayState == WindowDisplayState.maximised) {
          return;
        }
        // The workspace applies this delta in its own state and commits to the
        // backend only on release, so a drag no longer rebuilds the whole shell
        // on every pointer move.
        onDragMove?.call(d.delta);
      },
      child: Container(
        height: 34,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: DexSpace.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                window.session.application.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(
                  color: window.isFocused ? c.text : c.muted,
                ),
              ),
            ),
            if (window.session.status == WindowSessionStatus.streaming)
              _LiveBadge(rate: window.presentedFramesPerSecond),
          ],
        ),
      ),
    );

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: window.isFocused ? c.raised : c.surface,
        border: Border(
          bottom: BorderSide(color: c.line, width: DexStroke.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: draggableLabel),
          // Expand to edge-to-edge fullscreen — the reference's ↗ button. Only
          // a streaming window can fill the monitor, and only when the host
          // provides a fullscreen surface (absent in test harnesses).
          if (intents.fullscreen != null &&
              window.session.status == WindowSessionStatus.streaming)
            _WindowButton(
              icon: Icons.open_in_full,
              label: 'Fullscreen ${window.session.application.label}',
              onPressed: () => intents.fullscreen!(window.id),
            ),
          // Named for what it will do — Portrait or Landscape — rather than
          // being another ambiguous expand glyph.
          _WindowButton(
            icon: rotateActionLabel(window.geometry) == 'Portrait'
                ? Icons.stay_current_portrait
                : Icons.stay_current_landscape,
            label:
                '${rotateActionLabel(window.geometry)} '
                '${window.session.application.label}',
            onPressed: _rotate,
          ),
          _WindowButton(
            icon: Icons.remove,
            label: 'Minimise ${window.session.application.label}',
            onPressed: () => intents.setDisplayState(
              window.id,
              WindowDisplayState.minimised,
            ),
          ),
          _WindowButton(
            icon: window.displayState == WindowDisplayState.maximised
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
            label: window.displayState == WindowDisplayState.maximised
                ? 'Restore ${window.session.application.label}'
                : 'Maximise ${window.session.application.label}',
            onPressed: _toggleMaximise,
          ),
          _WindowButton(
            icon: Icons.close,
            label: 'Close ${window.session.application.label}',
            danger: true,
            onPressed: () => intents.close(window.id),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            // Draws small, but the target still clears the pointer minimum.
            width: DexHit.comfortable,
            height: 34,
            child: Icon(icon, size: 14, color: danger ? c.fault : c.muted),
          ),
        ),
      ),
    );
  }
}

/// The window body.
///
/// Every session status renders something honest. A `streaming` window with no
/// surface yet shows the skeleton, never an empty rectangle — an empty
/// rectangle reads as a broken app rather than one still starting.
class _Body extends StatelessWidget {
  const _Body({required this.window, required this.intents});

  final WorkspaceWindow window;
  final WorkspaceIntents intents;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;

    switch (window.session.status) {
      case WindowSessionStatus.failed:
        final OpenDexError? failure = window.session.error;
        return _Notice(
          colors: c,
          title: 'This app stopped',
          detail: failure?.message ?? 'The window closed unexpectedly.',
          // What to try, from the shared mapping. The message names what
          // failed; on its own it leaves the person with a stopped window and
          // a sentence about it.
          guidance: failure == null ? null : guidanceFor(failure),
          // The decoder's own account, offered rather than shown. It is built
          // from process output and can carry paths and device detail, so it
          // is copied on purpose — the same rule the boot screen follows.
          technicalDetails: failure?.technicalDetails,
          action: 'Try again',
          onAction: () => intents.retry(window.id),
        );
      case WindowSessionStatus.starting:
        return _Skeleton(colors: c, label: 'Opening…');
      case WindowSessionStatus.suspended:
        return _Dimmed(window: window, colors: c, label: 'Paused');
      case WindowSessionStatus.reconnecting:
        return _Dimmed(window: window, colors: c, label: 'Reconnecting…');
      case WindowSessionStatus.closed:
        return const SizedBox.shrink();
      case WindowSessionStatus.streaming:
        return _Surface(window: window, colors: c, intents: intents);
    }
    // Unreachable: the switch above is exhaustive over WindowSessionStatus.
    // ignore: dead_code
    return Text('', style: t.bodyMedium);
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.colors, required this.label});

  final DexColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.raised,
      child: Center(child: Text(label, style: DexTheme.data(colors, size: 11))),
    );
  }
}

/// Keeps the last frame visible under a scrim rather than blanking it: a paused
/// window that goes black is indistinguishable from a crashed one.
class _Dimmed extends StatelessWidget {
  const _Dimmed({
    required this.window,
    required this.colors,
    required this.label,
  });

  final WorkspaceWindow window;
  final DexColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bool hasFrames =
        window.surface != null || window.previewBuilder != null;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasFrames)
          _Surface(window: window, colors: colors)
        else
          ColoredBox(color: colors.raised),
        ColoredBox(color: colors.bg.withValues(alpha: 0.62)),
        Center(
          child: Text(
            label,
            style: DexTheme.data(colors, size: 11, color: colors.text),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.colors,
    required this.title,
    required this.detail,
    this.guidance,
    this.technicalDetails,
    this.action,
    this.onAction,
  });

  final DexColors colors;
  final String title;
  final String detail;

  /// What to try next. The detail says what failed.
  final String? guidance;

  /// Offered as a copy, never rendered.
  final String? technicalDetails;

  /// Optional: some notices explain a state the person cannot act on, and a
  /// button that does nothing is worse than no button.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return ColoredBox(
      color: colors.raised,
      child: Center(
        // Scrollable because a window can legitimately be dragged down to its
        // minimum 240x180, and this notice overflowed it by 68 px — the person
        // resizing got a striped overflow banner instead of their app.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DexSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: t.bodyLarge),
              const SizedBox(height: DexSpace.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: colors.muted),
              ),
              if (guidance case final String advice) ...<Widget>[
                const SizedBox(height: DexSpace.sm),
                Text(
                  advice,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium,
                ),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: DexSpace.md),
                OutlinedButton(onPressed: onAction, child: Text(action!)),
              ],
              if (technicalDetails case final String detail
                  when detail.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: DexSpace.sm),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: detail.trim())),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, DexHit.comfortable),
                  ),
                  icon: const Icon(Icons.content_copy, size: 14),
                  label: const Text('Copy technical details'),
                ),
                Text(
                  'Technical information about this computer and the phone. '
                  'Read it before sharing.',
                  textAlign: TextAlign.center,
                  style: DexTheme.data(colors, size: 11, color: colors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Android app's own pixels, inside our window.
///
/// This is the whole point of the product: until the backend produced a
/// texture, launching an app opened an external scrcpy window that floated
/// outside the desk and belonged to no one. [WindowSurface.textureId] is the
/// handle the host registers for that window's video, and Flutter's [Texture]
/// composites it into our tree like any other widget.
class _Surface extends StatefulWidget {
  const _Surface({
    required this.window,
    required this.colors,
    this.intents,
  });

  final WorkspaceWindow window;
  final DexColors colors;

  /// Null where there is nothing to offer. A dimmed window is paused or
  /// reconnecting by design, so telling its owner that no video is arriving
  /// would be describing the state they asked for — and a notice with no
  /// action behind it is a dead end.
  final WorkspaceIntents? intents;

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  /// Whether this window has ever put a frame on screen.
  ///
  /// This is the whole of what separates a stalled stream from a still one. A
  /// motionless app — a paused video, a page nobody is scrolling — presents
  /// zero frames in an interval and is working perfectly; the Live badge says
  /// as much, that the rate "counts changes, not speed". Only a window that
  /// has never once painted is broken, and no amount of waiting distinguishes
  /// the two, because a still screen stays still for as long as it likes.
  bool _everPresented = false;

  @override
  Widget build(BuildContext context) {
    final WorkspaceWindow window = widget.window;
    final DexColors colors = widget.colors;
    final WorkspaceIntents? intents = widget.intents;
    final WindowSurface? surface = window.surface;
    final WidgetBuilder? preview = window.previewBuilder;

    final double? rate = window.presentedFramesPerSecond;
    if (rate != null && rate > 0) _everPresented = true;

    if (surface == null && preview == null) {
      // Streaming, but the host has not registered a texture for this window.
      // Today that means the app really is running — in its own external
      // window — and the embedded view is not available yet. Say so, rather
      // than showing a blank rectangle the person has to interpret.
      return _Notice(
        colors: colors,
        title: '${window.session.application.label} is running',
        detail:
            'Its screen is still opening in a separate window. Showing it '
            'inside this one needs the video surface the desktop backend is '
            'still wiring up.',
      );
    }

    final Size pixels = surface != null
        ? Size(
            surface.pixelSize.width.toDouble(),
            surface.pixelSize.height.toDouble(),
          )
        : const Size(1080, 1920);

    // A texture exists and no frame has ever been painted into it. The window
    // is then a black rectangle with a lit Live badge, which is
    // indistinguishable from an app that happens to be showing black — so it
    // says so instead.
    //
    // The fade is the whole delay mechanism: every healthy stream reports no
    // frames for its first moments, and by animating up from nothing the
    // notice is cancelled long before it becomes visible. No timer ticks, and
    // once either end is reached the animation rests.
    //
    // Three seconds is now a courtesy rather than a guess: the condition is
    // already specific — a completed measurement of zero, on a window that has
    // never painted — so the delay only spares a window whose very first
    // interval happens to land empty while it is still opening.
    // Null is not zero. The backend emits a numeric rate on every completed
    // one-second sample, so null means no interval has finished yet, while an
    // explicit 0.0 means one finished and presented nothing. Coalescing the
    // two would accuse every window that has only just opened.
    final bool stalled = surface != null &&
        intents != null &&
        !_everPresented &&
        rate != null &&
        rate <= 0;

    final Widget video = ColoredBox(
      // Letterbox in black: a phone is taller than its window, and tinting the
      // bars would make the app look like it has a coloured border.
      color: const Color(0xFF000000),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: pixels.width,
          height: pixels.height,
          // No RepaintBoundary here on purpose. `TextureBox` already declares
          // `isRepaintBoundary => true` and `alwaysNeedsCompositing => true`,
          // and paints by adding a `TextureLayer` directly — so the stream is
          // already its own composited layer and a new frame never rasterises
          // the desk behind it. Wrapping it again only nests a second layer
          // that measurably does nothing.
          child: surface != null
              ? Texture(
                  textureId: surface.textureId,
                  // Pinned rather than changed: `low` is already the framework
                  // default. Stated so a future default change cannot silently
                  // switch a scaled video texture to nearest-neighbour, which
                  // shimmers on text as the scale drifts during a resize.
                  filterQuality: FilterQuality.low,
                )
              : Builder(builder: preview!),
        ),
      ),
    );

    // Nothing wrapped around the video unless there is something to say.
    //
    // This is a frame-cost decision, not a tidiness one. `TweenAnimationBuilder`
    // takes a `Tween`, and constructing one in build allocates an object per
    // window per frame — directly over the live texture, which is exactly the
    // shape of the allocation regression that cost playback smoothness before.
    // A healthy window now returns the texture untouched, and the fade only
    // exists while a window is actually silent, where there is no video being
    // dropped to pay for it.
    //
    // The cost is that recovery has no fade out: when frames start arriving the
    // notice disappears at once rather than dissolving. That is the right way
    // round — the animation exists to delay an accusation, not to decorate its
    // withdrawal.
    if (!stalled) return video;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        video,
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: stalled ? 1 : 0),
          duration: const Duration(seconds: 3),
          // Nothing at all for the first seven tenths, then a fade. A notice
          // held at a quarter opacity over live video is not a gentler
          // warning, it is a smear — and it would report a stall that has not
          // been established yet.
          curve: const Interval(0.7, 1, curve: DexMotion.arrive),
          builder: (BuildContext context, double t, Widget? child) => t == 0
              ? const SizedBox.shrink()
              : IgnorePointer(
                  ignoring: t < 1,
                  child: Opacity(opacity: t, child: child),
                ),
          child: _Notice(
            colors: colors,
            title: 'No video is arriving',
            detail:
                'The app is running on the phone and this window has a place '
                'to draw it, but no frame has reached the desk. Reopening the '
                'window starts a fresh stream.',
            action: 'Reopen',
            onAction: () => intents.retry(window.id),
          ),
        ),
      ],
    );
  }
}

/// Picks how this window's input is handled.
///
/// With a live surface and a backend that accepts pointers, events are
/// forwarded in surface pixels. Without either, the surface consumes its own
/// input — which is also the correct behaviour for a placeholder, since there
/// is nothing on the other end to send to.
WindowInput _inputFor(WorkspaceWindow window, WorkspaceIntents intents) {
  final WindowSurface? surface = window.surface;
  final void Function(String, WindowPointerSample)? send = intents.sendPointer;
  if (surface == null || send == null) {
    return const SurfaceConsumesInput();
  }
  return ForwardInputToBackend(
    surfacePixelSize: Size(
      surface.pixelSize.width.toDouble(),
      surface.pixelSize.height.toDouble(),
    ),
    onPointer: (PointerEvent event, Offset surfacePosition) {
      final WindowPointerSample? sample = windowPointerSample(
        event,
        surfacePosition,
      );
      if (sample != null) send(window.id, sample);
    },
  );
}

/// Says the stream is live, without putting a number in the title bar.
///
/// The title used to carry the screen-update rate. Relabelling it and adding a
/// tooltip was not enough — a bare "9/s" beside an app name still reads as a
/// performance grade, and it was twice mistaken for a fault. Measuring scrcpy
/// alone, with no FFmpeg, FIFO, texture or Flutter in the path, produced 7.1
/// frames a second on the same static video: the number was honest and the
/// presentation was not.
///
/// So the title says whether the stream is alive, which is the question a
/// glance is asking. The rate stays available on hover for diagnosis, and in
/// the link rail, where a number is expected to be a number.
///
/// Zero deliberately still reads as live. Android emits frames on change, so a
/// paused video and a dead pipeline are indistinguishable from this side — only
/// the backend knows a pipeline was retired, and it reports that as a failed
/// window instead.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.rate});

  /// Frames per second reaching the screen, when the backend reports them.
  ///
  /// Presented, never produced. This tooltip called the produced rate "screen
  /// updates" while the pipeline was putting a fifth of it on screen, which
  /// made the most visible number in the app the wrong one.
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final String detail = rate == null
        ? 'Streaming from the phone.'
        : 'Streaming from the phone.\n'
              'Frames on screen: ${rate!.round()} per second — a still screen '
              'sends few, so this counts changes, not speed.';

    return Semantics(
      label: 'Live',
      child: Tooltip(
        message: detail,
        child: Padding(
          padding: const EdgeInsets.only(right: DexSpace.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: c.trace,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: DexSpace.xs),
              Text('Live', style: DexTheme.data(c, size: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A window's live video surface and input with no frame, chrome, or title bar.
///
/// Used for immersive fullscreen: the phone fills the whole monitor and the
/// desk, taskbar and title bar are gone. It reuses the same [_Surface] and
/// input wiring as the framed [AppWindow] so a tap lands in the same place on
/// the phone whether the window is framed or fullscreen.
class WindowStage extends StatefulWidget {
  const WindowStage({
    required this.window,
    required this.intents,
    this.onExit,
    super.key,
  });

  final WorkspaceWindow window;
  final WorkspaceIntents intents;

  /// Leaves fullscreen. Null only in harnesses that render the stage alone; in
  /// the product the shell always supplies it, because a screen with no visible
  /// way out is the fault this exists to fix.
  final VoidCallback? onExit;

  @override
  State<WindowStage> createState() => _WindowStageState();
}

class _WindowStageState extends State<WindowStage> {
  /// The stage was a bare black rectangle. Esc and F11 both leave it and
  /// neither is discoverable, so anyone who pressed F11 once was looking at a
  /// screen with no apparent way back.
  ///
  /// Two answers, which is what every video player settled on: say it once on
  /// arrival, then keep a real control one pointer-move away.
  bool _hinting = true;
  bool _hovering = false;
  Timer? _hintTimer;

  /// Long enough to read, short enough not to sit on the video.
  static const Duration _hintFor = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(_hintFor, () {
      if (mounted) setState(() => _hinting = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    final TextTheme t = Theme.of(context).textTheme;
    final WindowInput input = _inputFor(widget.window, widget.intents);
    final bool showChrome = _hinting || _hovering;

    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          input.wrap(
            enabled: widget.window.isFocused,
            child: _Surface(
              window: widget.window,
              colors: c,
              intents: widget.intents,
            ),
          ),
          // A strip along the top rather than the whole surface: the rest of
          // the stage belongs to the app, and a MouseRegion over all of it
          // would swallow hover from the phone.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 96,
            child: MouseRegion(
              opaque: false,
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: IgnorePointer(
                ignoring: !showChrome,
                child: AnimatedOpacity(
                  opacity: showChrome ? 1 : 0,
                  duration: DexMotion.enabled(context)
                      ? DexDuration.standard
                      : Duration.zero,
                  curve: DexMotion.arrive,
                  child: _StageChrome(
                    label: widget.window.session.application.label,
                    colors: c,
                    text: t,
                    onExit: widget.onExit,
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

/// The bar that appears over the top of a fullscreen window.
class _StageChrome extends StatelessWidget {
  const _StageChrome({
    required this.label,
    required this.colors,
    required this.text,
    required this.onExit,
  });

  final String label;
  final DexColors colors;
  final TextTheme text;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DexSpace.xl,
          DexSpace.lg,
          DexSpace.lg,
          DexSpace.xl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: text.titleMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  // Names both keys. Someone who reached fullscreen by F11
                  // will try F11 to leave; someone who did not will try Esc.
                  Text(
                    'Press Esc or F11 to leave fullscreen',
                    style: text.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
            if (onExit != null)
              Tooltip(
                message: 'Exit fullscreen',
                child: IconButton(
                  onPressed: onExit,
                  color: Colors.white,
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: DexHit.primary,
                    minHeight: DexHit.primary,
                  ),
                  icon: const Icon(Icons.fullscreen_exit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
