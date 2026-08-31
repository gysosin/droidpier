import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'dex_glass.dart';
import 'dex_tokens.dart';
import 'wallpapers.dart';

/// A frosted panel: blurred backdrop, translucent fill, hairline edge.
///
/// Every panel on the desk goes through this so the blur radius and edge
/// treatment stay identical across the taskbar, widgets, menus and windows.
/// Building them by hand is how a glass design drifts into eleven slightly
/// different glasses.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.radius = DexRadius.panel,
    this.fill,
    this.stroke,
    this.padding = EdgeInsets.zero,
    this.blur,
    this.shadow = true,
    this.blurred = true,
    super.key,
  });

  final Widget child;
  final double radius;
  final Color? fill;
  final Color? stroke;
  final EdgeInsetsGeometry padding;
  final double? blur;

  /// Glass needs a shadow to separate from the wallpaper. Suppressed for
  /// panels that sit flush against an edge, where a shadow reads as a seam.
  final bool shadow;

  /// Whether to actually blur what is behind.
  ///
  /// A `BackdropFilter` re-reads and re-blurs its backdrop on **every frame the
  /// backdrop changes**. Over the wallpaper that is free — the wallpaper is
  /// static. Over a 60 fps video texture it is a full-panel blur sixty times a
  /// second, for decoration. Panels that can end up above a live stream pass
  /// false and take a slightly more opaque flat fill instead, which at these
  /// alphas is nearly indistinguishable and costs nothing.
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final glass = DexGlass.of(context);
    final shape = BorderRadius.circular(radius);
    // A panel blurs only if it asks to AND the surrounding scope allows it.
    // While a window is streaming, GlassBlurScope turns every backdrop blur on
    // the desk off: a BackdropFilter re-samples and re-blurs its backdrop every
    // frame the backdrop changes, and a live video texture changes it 30–60
    // times a second. Dozens of glass panels each re-blurring the whole scene
    // that often is what made the desk flicker continuously on Impeller.
    final bool effectiveBlurred = blurred && GlassBlurScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 32,
                  offset: Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: _backdrop(
          glass: glass,
          effectiveBlurred: effectiveBlurred,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _fill(glass, effectiveBlurred),
              borderRadius: shape,
              border: Border.all(color: stroke ?? glass.stroke, width: 1),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }

  /// Compensates for the missing blur: an unblurred panel needs more body to
  /// read as a surface rather than a tint.
  Color _fill(DexGlass glass, bool effectiveBlurred) {
    final Color base = fill ?? glass.fill;
    if (effectiveBlurred) return base;
    return Color.alphaBlend(
      base,
      base.withValues(alpha: 1),
    ).withValues(alpha: (base.a + 0.28).clamp(0.0, 1.0));
  }

  Widget _backdrop({
    required DexGlass glass,
    required bool effectiveBlurred,
    required Widget child,
  }) {
    if (!effectiveBlurred) return child;
    return BackdropFilter(
      filter: ui.ImageFilter.blur(
        sigmaX: blur ?? glass.blur,
        sigmaY: blur ?? glass.blur,
      ),
      child: child,
    );
  }
}

/// Switches backdrop blur off for every [GlassPanel] beneath it.
///
/// Placed at the desk root and disabled while any window is streaming, so the
/// whole glass surface stops re-blurring a live video texture every frame —
/// the continuous desk flicker on Impeller. Absent (no scope) means blur is
/// allowed, so panels outside a desk keep their frosted look.
class GlassBlurScope extends InheritedWidget {
  const GlassBlurScope({
    required this.enabled,
    required super.child,
    super.key,
  });

  /// Whether panels below may blur their backdrop.
  final bool enabled;

  /// True when blur is permitted here — the default when no scope is present.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassBlurScope>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(GlassBlurScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// The desk ground: a blue→indigo→violet gradient, a highlight thrown from the
/// top-right, and a darkening toward the bottom so the taskbar has something
/// to sit against.
///
/// This is the only thing in the product that is purely decorative, and it
/// earns its place — every glass surface above it is transparent, so without a
/// wallpaper there is nothing for them to be glass *over*.
class DeskWallpaper extends StatelessWidget {
  const DeskWallpaper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = DexGlass.of(context);
    // A wallpaper the person chose in Settings overrides the theme's gradient;
    // absent one, the theme default stands.
    final List<Color> colors = WallpaperScope.of(context) ?? glass.wallpaper;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.85, -0.9),
            radius: 1.4,
            colors: <Color>[
              glass.bloom,
              glass.bloom.withValues(alpha: 0),
              glass.vignette,
            ],
            stops: const <double>[0, 0.45, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}
